{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.lldap;
  declaredUsers = lib.attrValues cfg.users;
  declaredGroups = lib.attrValues cfg.groups;
  gatewayClient =
    if cfg.gateway.enable && builtins.hasAttr cfg.gateway.keycloak.client config.services.osmium.keycloak.clients
    then config.services.osmium.keycloak.clients.${cfg.gateway.keycloak.client}
    else null;
  gatewayIssuer = if cfg.gateway.enable then lib.removeSuffix "/" config.services.osmium.keycloak.issuer else "";
  gatewayRealmIssuer = if cfg.gateway.enable then "${gatewayIssuer}/realms/${cfg.gateway.keycloak.realm}" else "";
  stateDir = cfg.stateDir;
  runtimeDir = "/run/osmium-lldap";
  environmentFile = "${runtimeDir}/environment";
  ledger = "${stateDir}/.osmium-identities.json";
  settings = {
    ldap_host = cfg.ldapHost;
    ldap_port = cfg.ldapPort;
    http_host = cfg.httpHost;
    http_port = cfg.httpPort;
    http_url = cfg.httpUrl;
    ldap_base_dn = cfg.baseDn;
    ldap_user_dn = cfg.admin.username;
    ldap_user_email = cfg.admin.email;
    ldap_user_pass_file = cfg.admin.passwordFile;
    force_ldap_user_pass_reset = cfg.admin.passwordRotation == "always";
    jwt_secret_file = cfg.jwtSecretFile;
    # The native module otherwise generates a fallback secret when only the
    # file-backed environment override is configured.
    jwt_secret = "runtime-file-override";
    key_file = "${stateDir}/private_key";
    database_url = "sqlite://${stateDir}/users.db?mode=rwc";
    ldaps_options = {
      enabled = cfg.ldaps.enable;
      port = cfg.ldaps.port;
      cert_file = cfg.ldaps.certificateFile;
      key_file = cfg.ldaps.keyFile;
    };
  };
  runtimeEnvironment = pkgs.writeShellScript "osmium-lldap-runtime-environment" ''
    set -eu
    # Keep the directory traversable for runtime TLS files; individual
    # secret files remain root-readable only.
    install -d -m 0755 ${lib.escapeShellArg runtimeDir}
    umask 0077
    temporary=$(mktemp ${lib.escapeShellArg "${runtimeDir}/environment.XXXXXX"})
    printf 'LLDAP_KEY_SEED=%s\n' "$(cat ${lib.escapeShellArg cfg.keySeedFile})" > "$temporary"
    chmod 0400 "$temporary"
    mv -f "$temporary" ${lib.escapeShellArg environmentFile}
  '';
  reconcile = pkgs.writeShellScript "osmium-lldap-reconcile" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.openldap pkgs.lldap ]}
    api=${lib.escapeShellArg "http://127.0.0.1:${toString cfg.httpPort}"}
    base_dn=${lib.escapeShellArg cfg.baseDn}
    admin_username=${lib.escapeShellArg cfg.admin.username}
    admin_password_file=${lib.escapeShellArg cfg.admin.passwordFile}
    state=${lib.escapeShellArg stateDir}
    ledger=${lib.escapeShellArg ledger}
    runtime=${lib.escapeShellArg runtimeDir}

    [ -r "$admin_password_file" ] || { echo "LLDAP administrator password file is unavailable" >&2; exit 1; }
    admin_password=$(cat "$admin_password_file")
    [ -n "$admin_password" ] || { echo "LLDAP administrator password is empty" >&2; exit 1; }
    install -d -m 0700 "$runtime" "$state"
    for attempt in $(seq 1 30); do
      curl --silent --max-time 1 "$api/" >/dev/null 2>&1 && break
      [ "$attempt" = 30 ] && { echo "LLDAP HTTP listener did not become ready" >&2; exit 1; }
      sleep 1
    done
    if [ ! -e "$ledger" ]; then
      printf '%s\n' '{"schema_version":1,"users":[],"groups":[]}' > "$ledger"
      chmod 0600 "$ledger"
    fi
    jq -e '.schema_version == 1 and (.users | type == "array") and (.groups | type == "array")' "$ledger" >/dev/null

    login_payload=$(jq -cn --arg username "$admin_username" --arg password "$admin_password" '{username:$username,password:$password}')
    token=$(printf '%s' "$login_payload" | curl --fail --silent --show-error -H 'Content-Type: application/json' --data-binary @- "$api/auth/simple/login" | jq -r '.token // empty')
    [ -n "$token" ] || { echo "LLDAP administrator authentication failed" >&2; exit 1; }
    auth_config=$(mktemp "$runtime/graphql.XXXXXX")
    umask 0077
    printf 'header = "Authorization: Bearer %s"\n' "$token" > "$auth_config"
    chmod 0400 "$auth_config"
    trap 'rm -f "$auth_config"' EXIT

    graphql() {
      query=$1
      variables=''${2-'{}'}
      request=$(jq -cn --arg query "$query" --arg variables "$variables" '{query:$query,variables:($variables|fromjson)}')
      response=$(printf '%s' "$request" | curl --fail --silent --show-error --config "$auth_config" -H 'Content-Type: application/json' --data-binary @- "$api/api/graphql")
      jq -e '(.errors // []) | length == 0' <<<"$response" >/dev/null || {
        echo "LLDAP GraphQL request failed" >&2
        exit 1
      }
      jq -c '.data' <<<"$response"
    }

    users_json=$(graphql '{ users { id email displayName firstName lastName groups { id displayName } } }' | jq -c '.users')
    groups_json=$(graphql '{ groups { id displayName users { id } } }' | jq -c '.groups')
    new_salt() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
    fingerprint() { printf '%s%s' "$1" "$2" | sha256sum | cut -d' ' -f1; }
    set_password() {
      username=$1
      password=$2
      LLDAP_USER_PASSWORD="$password" lldap_set_password \
        --base-url "$api" --admin-username "$admin_username" --admin-password "$admin_password" \
        --username "$username" >/dev/null
    }
    authenticate_user() {
      username=$1
      password=$2
      password_tmp=$(mktemp "$runtime/password.XXXXXX")
      chmod 0400 "$password_tmp"
      printf '%s' "$password" > "$password_tmp"
      ldapsearch -x -H "ldap://127.0.0.1:${toString cfg.ldapPort}" \
        -D "uid=$username,ou=people,$base_dn" -y "$password_tmp" -b "$base_dn" "(uid=$username)" dn >/dev/null
      rm -f "$password_tmp"
    }

    ${lib.concatMapStringsSep "\n" (name:
      let user = cfg.users.${name};
      in ''
      username=${lib.escapeShellArg user.username}
      user_record=$(jq -c --arg declaration ${lib.escapeShellArg name} '[.users[] | select(.declaration == $declaration)] | if length == 1 then .[0] else empty end' "$ledger")
      existing=$(jq -c --arg username "$username" '[.[] | select(.id == $username)]' <<<"$users_json")
      existing_count=$(jq 'length' <<<"$existing")
      [ "$existing_count" != 2 ] || { echo "LLDAP user identity is ambiguous: $username" >&2; exit 1; }
      if [ "$existing_count" = 1 ] && [ -z "$user_record" ]; then
        echo "LLDAP user collides with an unmanaged identity: $username" >&2
        exit 1
      fi
      if [ "$existing_count" = 0 ]; then
        variables=$(jq -cn --arg id "$username" --arg email ${lib.escapeShellArg user.email} --arg display ${lib.escapeShellArg user.displayName} --arg first ${lib.escapeShellArg user.firstName} --arg last ${lib.escapeShellArg user.lastName} '{user:{id:$id,email:$email,displayName:$display,firstName:$first,lastName:$last}}')
        graphql 'mutation($user: CreateUserInput!) { createUser(user:$user) { id } }' "$variables" >/dev/null
        users_json=$(graphql '{ users { id email displayName firstName lastName groups { id displayName } } }' | jq -c '.users')
       else
         user_id=$(jq -r '.[0].id' <<<"$existing")
         variables=$(jq -cn --arg id "$user_id" --arg email ${lib.escapeShellArg user.email} --arg display ${lib.escapeShellArg user.displayName} --arg first ${lib.escapeShellArg user.firstName} --arg last ${lib.escapeShellArg user.lastName} '{user:{id:$id,email:$email,displayName:$display,firstName:$first,lastName:$last}}')
         graphql 'mutation($user: UpdateUserInput!) { updateUser(user:$user) { ok } }' "$variables" >/dev/null
       fi
       ${lib.optionalString (user.consumer != "directory") ''
         readonly_group_id=$(jq -r '.[] | select(.displayName == "lldap_strict_readonly") | .id' <<<"$groups_json" | head -n 1)
         [ -n "$readonly_group_id" ] || { echo "LLDAP strict-readonly group is unavailable for consumer ${lib.escapeShellArg name}" >&2; exit 1; }
         readonly_members=$(jq -c --arg group "$readonly_group_id" '.[] | select((.id|tostring) == $group) | [.users[].id]' <<<"$groups_json")
         if ! jq -e --arg user "$username" 'index($user) != null' <<<"$readonly_members" >/dev/null; then
           variables=$(jq -cn --arg user "$username" --arg group "$readonly_group_id" '{userId:$user,groupId:($group|tonumber)}')
           graphql 'mutation($userId: String!, $groupId: Int!) { addUserToGroup(userId:$userId,groupId:$groupId) { ok } }' "$variables" >/dev/null
         fi
       ''}
       password=$(cat ${lib.escapeShellArg user.passwordFile})
      [ -n "$password" ] || { echo "LLDAP user password is empty: ${lib.escapeShellArg name}" >&2; exit 1; }
      salt=$(jq -r --arg declaration ${lib.escapeShellArg name} '.users[] | select(.declaration == $declaration) | .salt // empty' "$ledger")
      [ -n "$salt" ] || salt=$(new_salt)
      fingerprint_value=$(fingerprint "$salt" "$password")
      recorded_fingerprint=$(jq -r --arg declaration ${lib.escapeShellArg name} '.users[] | select(.declaration == $declaration) | .fingerprint // empty' "$ledger")
      recorded_enabled=$(jq -r --arg declaration ${lib.escapeShellArg name} '.users[] | select(.declaration == $declaration) | .enabled // empty' "$ledger")
      if [ "$fingerprint_value" != "$recorded_fingerprint" ] || [ "$recorded_enabled" != ${lib.boolToString user.enabled} ]; then
        if [ ${lib.boolToString user.enabled} = true ]; then
          set_password "$username" "$password"
          authenticate_user "$username" "$password"
        else
          disabled_password=$(od -An -N48 -tx1 /dev/urandom | tr -d ' \n')
          set_password "$username" "$disabled_password"
        fi
      fi
      jq --arg declaration ${lib.escapeShellArg name} --arg username "$username" --arg email ${lib.escapeShellArg user.email} --arg salt "$salt" --arg fingerprint "$fingerprint_value" --argjson enabled ${lib.boolToString user.enabled} --arg groups_json ${lib.escapeShellArg (builtins.toJSON user.groups)} --arg removal_policy ${lib.escapeShellArg user.removalPolicy} '.users = ([.users[] | select(.declaration != $declaration)] + [{declaration:$declaration,username:$username,email:$email,salt:$salt,fingerprint:$fingerprint,enabled:$enabled,groups:($groups_json|fromjson),removal_policy:$removal_policy,status:"applied"}])' "$ledger" > "$ledger.next"
      chmod 0600 "$ledger.next"; mv -f "$ledger.next" "$ledger"
    '') (lib.attrNames cfg.users)}

    ${lib.concatMapStringsSep "\n" (name:
      let group = cfg.groups.${name};
      in ''
      display_name=${lib.escapeShellArg group.displayName}
      group_record=$(jq -c --arg declaration ${lib.escapeShellArg name} '[.groups[] | select(.declaration == $declaration)] | if length == 1 then .[0] else empty end' "$ledger")
      group_matches=$(jq -c --arg display "$display_name" '[.[] | select(.displayName == $display)]' <<<"$groups_json")
      group_count=$(jq 'length' <<<"$group_matches")
      [ "$group_count" != 2 ] || { echo "LLDAP group identity is ambiguous: $display_name" >&2; exit 1; }
      if [ "$group_count" = 1 ] && [ -z "$group_record" ]; then
        echo "LLDAP group collides with an unmanaged identity: $display_name" >&2
        exit 1
      fi
      if [ "$group_count" = 0 ]; then
        variables=$(jq -cn --arg name "$display_name" '{name:$name}')
        graphql 'mutation($name: String!) { createGroup(name:$name) { id } }' "$variables" >/dev/null
        groups_json=$(graphql '{ groups { id displayName users { id } } }' | jq -c '.groups')
      fi
      group_id=$(jq -r --arg display "$display_name" '.[] | select(.displayName == $display) | .id' <<<"$groups_json")
      jq --arg declaration ${lib.escapeShellArg name} --arg display_name "$display_name" --arg group_id "$group_id" --arg users_json ${lib.escapeShellArg (builtins.toJSON group.users)} --arg removal_policy ${lib.escapeShellArg group.removalPolicy} '.groups = ([.groups[] | select(.declaration != $declaration)] + [{declaration:$declaration,displayName:$display_name,id:($group_id|tonumber),users:($users_json|fromjson),removal_policy:$removal_policy,status:"applied"}])' "$ledger" > "$ledger.next"
      chmod 0600 "$ledger.next"; mv -f "$ledger.next" "$ledger"
    '') (lib.attrNames cfg.groups)}

    groups_json=$(graphql '{ groups { id displayName users { id } } }' | jq -c '.groups')
    ${lib.concatMapStringsSep "\n" (name:
      let group = cfg.groups.${name};
      in ''
      group_id=$(jq -r --arg declaration ${lib.escapeShellArg name} '.groups[] | select(.declaration == $declaration) | .id' "$ledger")
      current_members=$(jq -c --arg id "$group_id" '.[] | select((.id|tostring) == $id) | [.users[].id]' <<<"$groups_json")
      ${lib.concatMapStringsSep "\n" (usernameDeclaration:
        let user = cfg.users.${usernameDeclaration};
        in ''
        user_id=${lib.escapeShellArg user.username}
        if ! jq -e --arg id "$user_id" 'index($id) != null' <<<"$current_members" >/dev/null; then
          variables=$(jq -cn --arg user "$user_id" --arg group "$group_id" '{userId:$user,groupId:($group|tonumber)}')
          graphql 'mutation($userId: String!, $groupId: Int!) { addUserToGroup(userId:$userId,groupId:$groupId) { ok } }' "$variables" >/dev/null
        fi
      '') group.users}
      current_members=$(jq -c --arg id "$group_id" '.[] | select((.id|tostring) == $id) | [.users[].id]' <<<"$groups_json")
      ${lib.concatMapStringsSep "\n" (userName:
        let user = cfg.users.${userName};
        in ''
        managed_user=${lib.escapeShellArg user.username}
        if jq -e --arg user "$managed_user" 'index($user) != null' <<<"$current_members" >/dev/null && ! jq -e --arg declaration ${lib.escapeShellArg userName} --arg group ${lib.escapeShellArg name} '.groups[] | select(.declaration == $group) | (.users | index($declaration)) != null' "$ledger" >/dev/null; then
          variables=$(jq -cn --arg user "$managed_user" --arg group "$group_id" '{userId:$user,groupId:($group|tonumber)}')
          graphql 'mutation($userId: String!, $groupId: Int!) { removeUserFromGroup(userId:$userId,groupId:$groupId) { ok } }' "$variables" >/dev/null
        fi
      '') (lib.attrNames cfg.users)}
    '') (lib.attrNames cfg.groups)}

    declared_user_declarations=${lib.escapeShellArg (builtins.toJSON (lib.attrNames cfg.users))}
    stale_users=$(jq -c --arg declared "$declared_user_declarations" '($declared|fromjson) as $declared | [.users[] as $item | select(($declared | index($item.declaration)) == null) | $item]' "$ledger")
    while IFS= read -r stale_user; do
      [ -n "$stale_user" ] || continue
      if [ "$(jq -r '.removal_policy // "retain"' <<<"$stale_user")" = delete ]; then
        stale_username=$(jq -r '.username // empty' <<<"$stale_user")
        stale_matches=$(jq -c --arg username "$stale_username" '[.[] | select(.id == $username)]' <<<"$users_json")
        [ "$(jq length <<<"$stale_matches")" = 1 ] || { echo "LLDAP managed user ownership is ambiguous during removal: $stale_username" >&2; exit 1; }
        variables=$(jq -cn --arg id "$stale_username" '{userId:$id}')
        graphql 'mutation($userId: String!) { deleteUser(userId:$userId) { ok } }' "$variables" >/dev/null
        declaration=$(jq -r '.declaration' <<<"$stale_user")
        jq --arg declaration "$declaration" '.users = [.users[] | select(.declaration != $declaration)]' "$ledger" > "$ledger.next"
        chmod 0600 "$ledger.next"; mv -f "$ledger.next" "$ledger"
      fi
    done < <(jq -c '.[]' <<<"$stale_users")

    declared_group_declarations=${lib.escapeShellArg (builtins.toJSON (lib.attrNames cfg.groups))}
    stale_groups=$(jq -c --arg declared "$declared_group_declarations" '($declared|fromjson) as $declared | [.groups[] as $item | select(($declared | index($item.declaration)) == null) | $item]' "$ledger")
    while IFS= read -r stale_group; do
      [ -n "$stale_group" ] || continue
      if [ "$(jq -r '.removal_policy // "retain"' <<<"$stale_group")" = delete ]; then
        stale_group_id=$(jq -r '.id // empty' <<<"$stale_group")
        stale_display_name=$(jq -r '.displayName // empty' <<<"$stale_group")
        stale_matches=$(jq -c --arg id "$stale_group_id" --arg display "$stale_display_name" '[.[] | select((.id|tostring) == $id and .displayName == $display)]' <<<"$groups_json")
        [ "$(jq length <<<"$stale_matches")" = 1 ] || { echo "LLDAP managed group ownership is ambiguous during removal: $stale_display_name" >&2; exit 1; }
        variables=$(jq -cn --arg id "$stale_group_id" '{groupId:($id|tonumber)}')
        graphql 'mutation($groupId: Int!) { deleteGroup(groupId:$groupId) { ok } }' "$variables" >/dev/null
        declaration=$(jq -r '.declaration' <<<"$stale_group")
        jq --arg declaration "$declaration" '.groups = [.groups[] | select(.declaration != $declaration)]' "$ledger" > "$ledger.next"
        chmod 0600 "$ledger.next"; mv -f "$ledger.next" "$ledger"
      fi
    done < <(jq -c '.[]' <<<"$stale_groups")

    chmod 0600 "$ledger"
  '';
  observe = pkgs.writeShellScriptBin "osmium-lldap-observe" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq ]}
    output=""
    origin="runtime-observation"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --output) output=$2; shift 2 ;;
        --capture) origin="live-capture"; shift ;;
        *) echo "usage: osmium-lldap-observe [--capture] [--output FILE]" >&2; exit 2 ;;
      esac
    done
    api=${lib.escapeShellArg "http://127.0.0.1:${toString cfg.httpPort}"}
    admin_password_file=${lib.escapeShellArg cfg.admin.passwordFile}
    [ -s "$admin_password_file" ] || { echo "LLDAP administrator password file is unavailable" >&2; exit 2; }
    admin_password=$(cat "$admin_password_file")
    login_payload=$(jq -cn --arg username ${lib.escapeShellArg cfg.admin.username} --arg password "$admin_password" '{username:$username,password:$password}')
    token=$(printf '%s' "$login_payload" | curl --fail --silent --show-error -H 'Content-Type: application/json' --data-binary @- "$api/auth/simple/login" | jq -r '.token // empty')
    [ -n "$token" ] || { echo "LLDAP administrator authentication failed" >&2; exit 2; }
    graphql() {
      query=$1
      request=$(jq -cn --arg query "$query" '{query:$query,variables:{}}')
      printf '%s' "$request" | curl --fail --silent --show-error -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data-binary @- "$api/api/graphql"
    }
    users_json=$(graphql '{ users { id email displayName firstName lastName groups { id displayName } } }' | jq -cS 'if (.errors // []) | length > 0 then error("LLDAP GraphQL users query failed") else .data.users | map({username:.id,email:.email,displayName:(.displayName // ""),firstName:(.firstName // ""),lastName:(.lastName // ""),groups:(.groups // [] | map({displayName:.displayName}) | sort_by(.displayName))}) | sort_by(.username) end')
    groups_json=$(graphql '{ groups { id displayName users { id } } }' | jq -cS 'if (.errors // []) | length > 0 then error("LLDAP GraphQL groups query failed") else .data.groups | map({displayName:.displayName,users:(.users // [] | map(.id) | sort)}) | sort_by(.displayName) end')
    ledger_json='{}'
    if [ -r ${lib.escapeShellArg ledger} ]; then ledger_json=$(cat ${lib.escapeShellArg ledger}); fi
    report=$(jq -cnS \
      --arg origin "$origin" \
      --arg baseDn ${lib.escapeShellArg cfg.baseDn} \
      --arg httpUrl ${lib.escapeShellArg cfg.httpUrl} \
      --arg ldapHost ${lib.escapeShellArg cfg.ldapHost} \
      --argjson ldapPort ${toString cfg.ldapPort} \
      --argjson ldapsEnabled ${lib.boolToString cfg.ldaps.enable} \
      --argjson ldapsPort ${toString cfg.ldaps.port} \
      --argjson users "$users_json" --argjson groups "$groups_json" --argjson ledger "$ledger_json" \
      --argjson gatewayEnabled ${lib.boolToString cfg.gateway.enable} \
      --arg gatewayRealm ${lib.escapeShellArg (if cfg.gateway.enable then cfg.gateway.keycloak.realm else "")} \
      --arg gatewayClient ${lib.escapeShellArg (if cfg.gateway.enable then cfg.gateway.keycloak.client else "")} \
      --arg callback ${lib.escapeShellArg (if cfg.gateway.enable then cfg.gateway.callbackUrl else "")} \
      '($ledger.users // [] | map(.username)) as $managedUsers | ($ledger.groups // [] | map(.displayName)) as $managedGroups | {schema_version:2,source:{origin:$origin,method:"lldap-graphql",scope:"guest-runtime",review_only:true},provenance:{observed_fields:["users","groups","service","integrations"],ownership_source:".osmium-identities.json",secret_policy:"secret-bytes-excluded"},complete:false,activation_ready:false,service:{baseDn:$baseDn,httpUrl:$httpUrl,ldapHost:$ldapHost,ldapPort:$ldapPort,ldapsEnabled:$ldapsEnabled,ldapsPort:$ldapsPort,tls:{certificateFile:{unresolved:true},keyFile:{unresolved:true}}},users:[$users[] | . as $user | $user + {ownership:(if ($managedUsers | index($user.username)) != null then "managed-or-ambiguous" else "unmanaged" end)}],groups:[$groups[] | . as $group | $group + {ownership:(if ($managedGroups | index($group.displayName)) != null then "managed-or-ambiguous" else "unmanaged" end)}],integrations:{gateway:{enabled:$gatewayEnabled,keycloakRealm:(if $gatewayEnabled then $gatewayRealm else null end),keycloakClient:(if $gatewayEnabled then $gatewayClient else null end),callbackUrl:(if $gatewayEnabled then $callback else null end),clientSecretFile:{unresolved:true},cookieSecretFile:{unresolved:true},tls:{certificateFile:{unresolved:true},keyFile:{unresolved:true}}}},ownership:{ledgerPresent:(($ledger.schema_version // 0) == 1),managedUsers:($ledger.users // [] | map(.username) | sort),managedGroups:($ledger.groups // [] | map(.displayName) | sort)},secrets:{excluded:true,unresolved:["admin.passwordFile","jwtSecretFile","keySeedFile","ldaps.certificateFile","ldaps.keyFile","users.*.passwordFile","integrations.gateway.clientSecretFile","integrations.gateway.cookieSecretFile","integrations.gateway.tls.*"]},findings:[{code:"secret-excluded",scope:"all"},{code:"password-material-unavailable",scope:"users"},{code:"tls-material-unavailable",scope:"service"},{code:"ownership-requires-ledger-review",scope:"users-and-groups"},{code:"unsupported-state-review-required",scope:"external-schema-and-password-policy"}]}')
    if [ -n "$output" ]; then install -d -m 0750 "$(dirname "$output")"; printf '%s\n' "$report" > "$output"; else printf '%s\n' "$report"; fi
  '';
  capture = pkgs.writeShellScriptBin "osmium-lldap-capture" ''
    exec ${observe}/bin/osmium-lldap-observe --capture "$@"
  '';
  candidate = pkgs.writeShellScriptBin "osmium-lldap-candidate" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.jq ]}
    [ "''${1:-}" = "--input" ] && [ -r "''${2:-}" ] || { echo "usage: osmium-lldap-candidate --input OBSERVATION" >&2; exit 2; }
    jq -cS '
      def key($prefix; $value): ($prefix + "_" + ($value | ascii_downcase | gsub("[^a-z0-9]+"; "_") | gsub("^_+|_+$"; "")));
      . as $o |
      ($o.users | map({key:key("user"; .username),value:{username:.username,email:.email,displayName:.displayName,firstName:.firstName,lastName:.lastName,groups:([.groups[].displayName] | sort),passwordFile:{unresolved:true},ownership:.ownership}}) | from_entries) as $users |
      ($o.groups | map({key:key("group"; .displayName),value:{displayName:.displayName,users:(.users | sort),removalPolicy:"retain",ownership:.ownership}}) | from_entries) as $groups |
      {schema_version:2,complete:false,activation_ready:false,provenance:(($o.source // {}) + {conversion:"review-only",observed_at:($o.observed_at // null),derived_from:"runtime-observation"}),declaration:{services:{osmium:{lldap:{baseDn:$o.service.baseDn,httpUrl:$o.service.httpUrl,ldapHost:$o.service.ldapHost,ldapPort:$o.service.ldapPort,ldaps:{enable:$o.service.ldapsEnabled,port:$o.service.ldapsPort},users:$users,groups:$groups,gateway:$o.integrations.gateway}}}},secrets:{excluded:true},unresolved:($o.secrets.unresolved + ["users.*.passwordFile"]),ownership:$o.ownership,findings:(($o.findings // []) + [{code:"operator-review-required",scope:"all"},{code:"unresolved-secret-reference",scope:"secret-backed-fields"}])}' "$2"
  '';
  drift = pkgs.writeShellScriptBin "osmium-lldap-drift" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.jq ]}
    observation=""; declared=""; output=""
    while [ "$#" -gt 0 ]; do case "$1" in --observation) observation=$2; shift 2;; --declared) declared=$2; shift 2;; --output) output=$2; shift 2;; *) echo "usage: osmium-lldap-drift --observation FILE --declared FILE [--output FILE]" >&2; exit 2;; esac; done
    [ -r "$observation" ] && [ -r "$declared" ] || { echo "observation and declared files are required" >&2; exit 2; }
    result=$(jq -cS --slurpfile declared "$declared" '
      def diffs($a;$b;$fields): [$fields[] as $f | select(($a[$f] // null) != ($b[$f] // null)) | {field:$f,observed:($a[$f] // null),declared:($b[$f] // null)}];
      . as $o | $declared[0] as $d |
      ([.users[] as $u | ($d.users // {} | to_entries | map(select(.value.username == $u.username)) | first | .value) as $old | {resource:"user",name:$u.username,kind:(if $old == null then "unmanaged" elif (diffs($u;$old;["email","displayName","firstName","lastName","groups"]) | length) == 0 then "matching" else "changed" end),differences:diffs($u;$old;["email","displayName","firstName","lastName","groups"])}] + [.groups[] as $g | ($d.groups // {} | to_entries | map(select(.value.displayName == $g.displayName)) | first | .value) as $old | {resource:"group",name:$g.displayName,kind:(if $old == null then "unmanaged" elif (diffs($g;$old;["users"]) | length) == 0 then "matching" else "changed" end),differences:diffs($g;$old;["users"])}]) as $changes |
      {schema_version:2,complete:false,activation_ready:false,provenance:(($o.source // {}) + {conversion:"review-only-drift",derived_from:"runtime-observation"}),changes:$changes,candidate:$o,secrets:{excluded:true},findings:(($o.findings // []) + [{code:"non-mutating-review-only",scope:"all"},{code:"unresolved-secret-reference",scope:"secret-backed-fields"}])}' "$observation")
    if [ -n "$output" ]; then printf '%s\n' "$result" > "$output"; else printf '%s\n' "$result"; fi
  '';
in
{
  options.services.osmium.lldap = {
    enable = lib.mkEnableOption "the Osmium LLDAP service";
    package = lib.mkPackageOption pkgs "lldap" { };
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/lldap";
      description = "Persistent LLDAP SQLite state directory.";
    };
    baseDn = lib.mkOption {
      type = lib.types.strMatching "(dc=[A-Za-z0-9-]+)(,dc=[A-Za-z0-9-]+)*";
      default = "dc=example,dc=com";
      description = "LLDAP LDAP base DN.";
    };
    httpUrl = lib.mkOption {
      type = lib.types.strMatching "https?://[^[:space:]]+";
      default = "https://lldap.example.invalid";
      description = "Public HTTPS URL used in LLDAP links.";
    };
    ldapHost = lib.mkOption { type = lib.types.str; default = "0.0.0.0"; description = "LDAP listener address."; };
    ldapPort = lib.mkOption { type = lib.types.port; default = 3890; description = "Guest LDAP port."; };
    hostLdapPort = lib.mkOption { type = lib.types.port; default = 3890; description = "Forwarded host LDAP port."; };
    httpHost = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "Loopback HTTP listener address."; };
    httpPort = lib.mkOption { type = lib.types.port; default = 17170; description = "Loopback HTTP administration port."; };
    hostHttpPort = lib.mkOption { type = lib.types.nullOr lib.types.port; default = null; description = "Optional HTTP host forwarding, intended only for a gateway."; };
    admin = {
      username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "admin"; description = "Initial LLDAP administrator username."; };
      email = lib.mkOption { type = lib.types.strMatching "[^[:space:]@]+@[^[:space:]@]+"; default = "admin@example.invalid"; description = "Initial LLDAP administrator email."; };
      passwordFile = lib.mkOption { type = lib.types.path; description = "Runtime administrator password file."; };
      passwordRotation = lib.mkOption { type = lib.types.enum [ "bootstrap" "always" ]; default = "bootstrap"; description = "Whether administrator password changes are applied declaratively."; };
    };
    jwtSecretFile = lib.mkOption { type = lib.types.path; description = "Runtime JWT secret file."; };
    keySeedFile = lib.mkOption { type = lib.types.path; description = "Runtime LLDAP password-key seed file."; };
    ldaps = {
      enable = lib.mkEnableOption "LLDAP LDAPS" // { default = true; };
      port = lib.mkOption { type = lib.types.port; default = 6360; description = "Guest LDAPS port."; };
      hostPort = lib.mkOption { type = lib.types.port; default = 6360; description = "Forwarded host LDAPS port."; };
      certificateFile = lib.mkOption { type = lib.types.path; default = "/run/osmium-lldap/certificate.pem"; description = "Runtime LDAPS certificate."; };
      keyFile = lib.mkOption { type = lib.types.path; default = "/run/osmium-lldap/key.pem"; description = "Runtime LDAPS private key."; };
    };
    users = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; description = "Stable LLDAP username."; };
          email = lib.mkOption { type = lib.types.strMatching "[^[:space:]@]+@[^[:space:]@]+"; description = "LLDAP user email address."; };
          displayName = lib.mkOption { type = lib.types.str; default = ""; description = "LLDAP display name."; };
          firstName = lib.mkOption { type = lib.types.str; default = ""; description = "LLDAP first name."; };
          lastName = lib.mkOption { type = lib.types.str; default = ""; description = "LLDAP last name."; };
          enabled = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the declared user can authenticate."; };
          groups = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Declared group keys for this user."; };
          passwordFile = lib.mkOption { type = lib.types.path; description = "Runtime user password file."; };
           removalPolicy = lib.mkOption { type = lib.types.enum [ "retain" "delete" ]; default = "retain"; description = "Whether removal may delete the ownership-proven user."; };
          consumer = lib.mkOption { type = lib.types.enum [ "directory" "keycloak" "authelia" ]; default = "directory"; description = "Optional restricted consumer role for this managed bind user."; };
        };
      }));
      description = "Declarative LLDAP users.";
    };
    groups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          displayName = lib.mkOption { type = lib.types.strMatching ".+"; description = "Stable LLDAP group display name."; };
          users = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Declared user keys in this group."; };
          removalPolicy = lib.mkOption { type = lib.types.enum [ "retain" "delete" ]; default = "retain"; description = "Whether removal may delete the ownership-proven group."; };
        };
      }));
      description = "Declarative LLDAP groups.";
    };
    reverseConfiguration.enable = lib.mkEnableOption "review-only LLDAP observation tooling";
    gateway = {
      enable = lib.mkEnableOption "the Keycloak-protected LLDAP administration gateway";
      keycloak = {
        realm = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; description = "Stable Keycloak realm declaration key."; };
        client = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._:-]+"; description = "Stable Keycloak confidential-client declaration key."; };
      };
      callbackUrl = lib.mkOption { type = lib.types.strMatching "https://[^[:space:]]+/oauth2/callback"; description = "Exact HTTPS oauth2-proxy callback URL."; };
      clientSecretFile = lib.mkOption { type = lib.types.path; description = "Runtime Keycloak client-secret file."; };
      cookieSecretFile = lib.mkOption { type = lib.types.path; description = "Runtime oauth2-proxy cookie-secret file."; };
      tls = {
        certificateFile = lib.mkOption { type = lib.types.path; description = "Runtime HTTPS certificate for the browser endpoint."; };
        keyFile = lib.mkOption { type = lib.types.path; description = "Runtime HTTPS private key for the browser endpoint."; };
      };
      browserPort = lib.mkOption { type = lib.types.port; default = 17172; description = "Guest HTTPS browser gateway port."; };
      hostBrowserPort = lib.mkOption { type = lib.types.port; default = 17172; description = "MicroVM host-forwarded HTTPS browser gateway port."; };
      machinePort = lib.mkOption { type = lib.types.port; default = 17173; description = "Loopback-only guest GraphQL machine route port."; };
      operator = {
        allowedEmails = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Exact Keycloak email claims allowed through the browser gateway."; };
        groupClaimName = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._:-]+"; default = "groups"; description = "OIDC claim containing allowed operator groups."; };
        allowedGroups = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Keycloak groups allowed through the browser gateway."; };
      };
    };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = lib.hasPrefix "/var/lib/" (toString stateDir); message = "services.osmium.lldap.stateDir must be below /var/lib."; }
      { assertion = stateDir == "/var/lib/lldap"; message = "services.osmium.lldap.stateDir must be /var/lib/lldap because the native NixOS module owns this StateDirectory."; }
      { assertion = lib.hasPrefix "https://" cfg.httpUrl; message = "services.osmium.lldap.httpUrl must use HTTPS."; }
      { assertion = cfg.admin.passwordFile != cfg.jwtSecretFile && cfg.admin.passwordFile != cfg.keySeedFile && cfg.jwtSecretFile != cfg.keySeedFile; message = "LLDAP runtime secret files must be distinct."; }
      { assertion = !cfg.ldaps.enable || (cfg.ldaps.certificateFile != cfg.ldaps.keyFile); message = "LLDAP LDAPS certificate and key files must be distinct."; }
      { assertion = cfg.hostLdapPort != cfg.hostHttpPort || cfg.hostHttpPort == null; message = "LLDAP host LDAP and HTTP ports must differ."; }
      { assertion = !cfg.ldaps.enable || cfg.ldaps.hostPort != cfg.hostLdapPort; message = "LLDAP host LDAP and LDAPS ports must differ."; }
      { assertion = lib.length (lib.unique (map (user: user.username) declaredUsers)) == lib.length declaredUsers; message = "LLDAP user usernames must be unique."; }
      { assertion = lib.all (user: builtins.match "[A-Za-z0-9._-]+" user.username != null) declaredUsers; message = "LLDAP user usernames must contain only letters, numbers, dots, underscores, and hyphens."; }
      { assertion = lib.length (lib.unique (map (user: user.email) declaredUsers)) == lib.length declaredUsers; message = "LLDAP user email addresses must be unique."; }
      { assertion = lib.length (lib.unique (map (user: user.consumer) (lib.filter (user: user.consumer != "directory") declaredUsers))) == lib.length (lib.filter (user: user.consumer != "directory") declaredUsers); message = "LLDAP consumer bind-user roles must be unique."; }
      { assertion = lib.all (user: user.consumer == "directory" || user.username != cfg.admin.username) declaredUsers; message = "LLDAP consumer bind users must not reuse the administrator identity."; }
      { assertion = lib.length (lib.unique (map (group: group.displayName) declaredGroups)) == lib.length declaredGroups; message = "LLDAP group display names must be unique."; }
      { assertion = lib.all (user: lib.hasPrefix "/" (toString user.passwordFile) && !lib.hasPrefix "/nix/store/" (toString user.passwordFile)) declaredUsers; message = "LLDAP user password files must be absolute runtime paths outside /nix/store."; }
      { assertion = lib.all (user: lib.all (group: builtins.hasAttr group cfg.groups) user.groups) declaredUsers; message = "LLDAP user memberships must reference declared groups."; }
      { assertion = lib.all (group: lib.all (user: builtins.hasAttr user cfg.users) group.users) declaredGroups; message = "LLDAP group memberships must reference declared users."; }
      { assertion = !cfg.gateway.enable || config.services.osmium.keycloak.enable; message = "LLDAP administration gateway requires the Osmium Keycloak module to be enabled."; }
      { assertion = !cfg.gateway.enable || gatewayClient != null; message = "LLDAP administration gateway must reference an existing Keycloak client declaration."; }
      { assertion = !cfg.gateway.enable || (gatewayClient != null && gatewayClient.realm == cfg.gateway.keycloak.realm && !gatewayClient.public && gatewayClient.secretFile == cfg.gateway.clientSecretFile); message = "LLDAP administration gateway requires a confidential client in the selected realm with the same runtime secret-file reference."; }
      { assertion = !cfg.gateway.enable || (gatewayClient != null && lib.elem "authorization-code" gatewayClient.flows && lib.elem cfg.gateway.callbackUrl gatewayClient.redirectUris); message = "LLDAP administration gateway callbackUrl must be an exact authorization-code redirect URI on the selected Keycloak client."; }
      { assertion = !cfg.gateway.enable || lib.hasPrefix "https://" cfg.gateway.callbackUrl; message = "LLDAP administration gateway callbackUrl must use HTTPS."; }
      { assertion = !cfg.gateway.enable || (cfg.gateway.operator.allowedEmails != [ ] || cfg.gateway.operator.allowedGroups != [ ]); message = "LLDAP administration gateway operator authorization must allow at least one exact email or group."; }
      { assertion = !cfg.gateway.enable || (cfg.httpHost == "127.0.0.1" || cfg.httpHost == "::1" || cfg.httpHost == "localhost"); message = "LLDAP administration gateway requires the LLDAP HTTP upstream to bind to loopback."; }
      { assertion = !cfg.gateway.enable || cfg.gateway.browserPort != cfg.gateway.machinePort && cfg.gateway.browserPort != cfg.httpPort && cfg.gateway.machinePort != cfg.httpPort; message = "LLDAP administration gateway browser, machine, and upstream ports must be distinct."; }
      { assertion = !cfg.gateway.enable || cfg.gateway.hostBrowserPort != cfg.hostLdapPort && (!cfg.ldaps.enable || cfg.gateway.hostBrowserPort != cfg.ldaps.hostPort); message = "LLDAP administration gateway host port must not collide with an LDAP listener."; }
      { assertion = !cfg.gateway.enable || lib.all (path: lib.hasPrefix "/" (toString path) && !lib.hasPrefix "/nix/store/" (toString path)) [ cfg.gateway.clientSecretFile cfg.gateway.cookieSecretFile cfg.gateway.tls.certificateFile cfg.gateway.tls.keyFile ]; message = "LLDAP administration gateway secrets and TLS inputs must be absolute runtime paths outside the Nix store."; }
      { assertion = !cfg.gateway.enable || cfg.gateway.tls.certificateFile != cfg.gateway.tls.keyFile; message = "LLDAP administration gateway TLS certificate and key files must be distinct."; }
    ];

    services.lldap = {
      enable = true;
      package = cfg.package;
      database.type = "sqlite";
      database.createLocally = true;
      inherit environmentFile;
      settings = settings;
      silenceForceUserPassResetWarning = true;
    };

    users.users.lldap = {
      isSystemUser = true;
      group = "lldap";
      home = stateDir;
      createHome = true;
    };
    users.groups.lldap = { };
    systemd.services.lldap.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "lldap";
      Group = lib.mkForce "lldap";
      StateDirectory = lib.mkForce "";
      WorkingDirectory = lib.mkForce stateDir;
      ReadWritePaths = [ stateDir ];
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -o lldap -g lldap -m 0750 ${lib.escapeShellArg stateDir}";
    };

    systemd.services.osmium-lldap-runtime-environment = {
      description = "Prepare runtime-only LLDAP secret environment";
      wantedBy = [ "multi-user.target" ];
      before = [ "lldap.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0077"; ExecStart = runtimeEnvironment; };
    };
    systemd.services.lldap = {
      after = [ "osmium-lldap-runtime-environment.service" ];
      requires = [ "osmium-lldap-runtime-environment.service" ];
    };
    systemd.services.osmium-lldap-reconcile = {
      description = "Reconcile declarative LLDAP identities";
      wantedBy = [ "multi-user.target" ];
      after = [ "lldap.service" ];
      requires = [ "lldap.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; Group = "root"; ExecStart = reconcile; UMask = "0077"; };
    };
    environment.systemPackages = lib.optionals cfg.reverseConfiguration.enable [ observe capture candidate drift ];
    environment.persistence."/persistent".directories = [ { directory = stateDir; user = "lldap"; group = "lldap"; mode = "0750"; } ];
    services.oauth2-proxy = lib.mkIf cfg.gateway.enable {
      enable = true;
      provider = "oidc";
      clientID = gatewayClient.clientId;
      clientSecretFile = cfg.gateway.clientSecretFile;
      cookie.secretFile = cfg.gateway.cookieSecretFile;
      cookie.secure = true;
      oidcIssuerUrl = gatewayRealmIssuer;
      redirectURL = cfg.gateway.callbackUrl;
      httpAddress = "127.0.0.1:4181";
      upstream = "static://202";
      reverseProxy = true;
      setXauthrequest = false;
      trustedProxyIP = [ "127.0.0.1/32" ];
      passAccessToken = false;
      passBasicAuth = false;
      scope = lib.concatStringsSep " " [ "openid" "profile" "email" ];
      email.addresses = lib.concatStringsSep "\n" cfg.gateway.operator.allowedEmails;
      extraConfig = {
        "code-challenge-method" = "S256";
      } // lib.optionalAttrs (cfg.gateway.operator.allowedGroups != [ ]) {
        "oidc-groups-claim" = cfg.gateway.operator.groupClaimName;
        "allowed-group" = lib.concatStringsSep "," cfg.gateway.operator.allowedGroups;
      };
    };
    systemd.services.oauth2-proxy = lib.mkIf cfg.gateway.enable {
      after = [ "osmium-keycloak-reconcile.service" ];
      requires = [ "osmium-keycloak-reconcile.service" ];
    };
    services.nginx = lib.mkIf cfg.gateway.enable {
      enable = true;
      virtualHosts."lldap-browser" = {
        addSSL = true;
        listen = [{ addr = "0.0.0.0"; port = cfg.gateway.browserPort; ssl = true; }];
        sslCertificate = cfg.gateway.tls.certificateFile;
        sslCertificateKey = cfg.gateway.tls.keyFile;
        locations."/oauth2/" = {
          proxyPass = "http://127.0.0.1:4181";
          extraConfig = ''
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto https;
          '';
        };
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          extraConfig = ''
            auth_request /oauth2/auth;
            error_page 401 =302 /oauth2/sign_in?rd=$request_uri;
            proxy_set_header Authorization "";
            proxy_set_header X-Forwarded-User "";
            proxy_set_header X-Forwarded-Email "";
            proxy_set_header X-Auth-Request-User "";
            proxy_set_header X-Auth-Request-Email "";
            proxy_set_header X-Auth-Request-Groups "";
          '';
        };
      };
      virtualHosts."lldap-machine" = {
        listen = [{ addr = "127.0.0.1"; port = cfg.gateway.machinePort; }];
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          extraConfig = ''
            proxy_set_header Authorization "";
            proxy_set_header X-Forwarded-User "";
            proxy_set_header X-Forwarded-Email "";
            proxy_set_header X-Auth-Request-User "";
            proxy_set_header X-Auth-Request-Email "";
            proxy_set_header X-Auth-Request-Groups "";
          '';
        };
      };
    };
    systemd.paths.osmium-lldap-gateway = lib.mkIf cfg.gateway.enable {
      wantedBy = [ "multi-user.target" ];
      pathConfig = { PathChanged = [ cfg.gateway.clientSecretFile cfg.gateway.cookieSecretFile cfg.gateway.tls.certificateFile cfg.gateway.tls.keyFile ]; Unit = "osmium-lldap-gateway-reload.service"; };
    };
    systemd.services.osmium-lldap-gateway-reload = lib.mkIf cfg.gateway.enable {
      description = "Reload LLDAP administration gateway runtime credentials";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "osmium-lldap-gateway-reload" ''
          set -eu
          ${pkgs.systemd}/bin/systemctl try-restart oauth2-proxy.service nginx.service
        '';
      };
    };
  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = [
      { from = "host"; proto = "tcp"; host.port = cfg.hostLdapPort; guest.port = cfg.ldapPort; }
    ] ++ lib.optional cfg.ldaps.enable { from = "host"; proto = "tcp"; host.port = cfg.ldaps.hostPort; guest.port = cfg.ldaps.port; }
      ++ lib.optional cfg.gateway.enable { from = "host"; proto = "tcp"; host.port = cfg.gateway.hostBrowserPort; guest.port = cfg.gateway.browserPort; };
    networking.firewall.allowedTCPPorts = [ cfg.ldapPort ] ++ lib.optional cfg.ldaps.enable cfg.ldaps.port ++ lib.optional cfg.gateway.enable cfg.gateway.browserPort;
  });
}
