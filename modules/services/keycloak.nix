{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.keycloak;
  realms = lib.attrValues cfg.realms;
  clientScopes = lib.attrValues cfg.clientScopes;
  realmRoles = lib.attrValues cfg.realmRoles;
  clientRoles = lib.attrValues cfg.clientRoles;
  groups = lib.attrValues cfg.groups;
  clients = lib.attrValues cfg.clients;
  users = lib.attrValues cfg.users;
  ldapFederations = lib.attrValues cfg.ldapFederations;
  passwordClient = lib.findFirst (client: client.public && builtins.elem "password" client.flows) null clients;
  stateDir = cfg.stateDir;
  ledger = "${stateDir}/.osmium-ledger.json";
  runtimeDir = "/run/osmium-keycloak";
  desired = pkgs.writeText "osmium-keycloak-desired.json" (builtins.toJSON {
    schema_version = 1;
    realms = lib.mapAttrs
      (name: realm: {
        inherit name;
        enabled = realm.enabled;
        displayName = realm.displayName;
        clients = lib.mapAttrs
          (_: client: {
            clientId = client.clientId;
            public = client.public;
            redirectUris = client.redirectUris;
            webOrigins = client.webOrigins;
          })
          (lib.filterAttrs (_: client: client.realm == name) cfg.clients);
        users = lib.mapAttrs
          (_: user: {
            username = user.username;
            enabled = user.enabled;
            email = user.email;
            firstName = user.firstName;
            lastName = user.lastName;
            emailVerified = user.emailVerified;
            requiredActions = user.requiredActions;
            groups = user.groups;
            realmRoles = user.realmRoles;
          })
          (lib.filterAttrs (_: user: user.realm == name) cfg.users);
        clientScopes = lib.filterAttrs (_: scope: scope.realm == name) cfg.clientScopes;
        realmRoles = lib.filterAttrs (_: role: role.realm == name) cfg.realmRoles;
        groups = lib.filterAttrs (_: group: group.realm == name) cfg.groups;
      })
      cfg.realms;
    clientScopes = cfg.clientScopes;
    realmRoles = cfg.realmRoles;
    clientRoles = cfg.clientRoles;
    groups = cfg.groups;
    clients = lib.mapAttrs
      (name: client: {
        inherit name;
        realm = client.realm;
        clientId = client.clientId;
        enabled = client.enabled;
        public = client.public;
        redirectUris = client.redirectUris;
        webOrigins = client.webOrigins;
        protocol = client.protocol;
        flows = client.flows;
        consentRequired = client.consentRequired;
        scopes = client.scopes;
        includeGroupClaims = client.includeGroupClaims;
        realmRoles = client.realmRoles;
        clientRoles = client.clientRoles;
        secretFile = lib.optionalAttrs (!client.public) { unresolved = true; path = client.secretFile; };
      })
      cfg.clients;
    users = lib.mapAttrs
      (name: user: {
        inherit name;
        realm = user.realm;
        username = user.username;
        enabled = user.enabled;
        email = user.email;
        firstName = user.firstName;
        lastName = user.lastName;
        emailVerified = user.emailVerified;
        requiredActions = user.requiredActions;
        groups = user.groups;
        realmRoles = user.realmRoles;
        passwordFile = { unresolved = true; path = user.passwordFile; };
      })
      cfg.users;
    ldapFederations = lib.mapAttrs
      (_: federation: {
        realm = federation.realm;
        directory = federation.directory;
        connectionUrl = federation.connectionUrl;
        usersDn = federation.usersDn;
        groupsDn = federation.groupsDn;
        bindUser = federation.bindUser;
        trustCertificateFile = federation.trustCertificateFile;
        usernameAttribute = federation.usernameAttribute;
        groupNameAttribute = federation.groupNameAttribute;
        membershipAttribute = federation.membershipAttribute;
        secretFile = { unresolved = true; path = federation.bindPasswordFile; };
      })
      cfg.ldapFederations;
  });
  signingKeys = cfg.signingKeys;
  reconciler = pkgs.writeShellScript "osmium-keycloak-reconcile" ''
     set -eu
     PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.openldap pkgs.openssl ]}
    api=${lib.escapeShellArg "http://127.0.0.1:${toString cfg.httpPort}${cfg.httpPath}"}
    api=''${api%/}
    ledger=${lib.escapeShellArg ledger}
    desired=${lib.escapeShellArg desired}
    state=${lib.escapeShellArg stateDir}
     runtime=${lib.escapeShellArg runtimeDir}
     admin_file=${lib.escapeShellArg cfg.admin.passwordFile}
     admin_cache="$runtime/admin-password"
     [ -r "$admin_file" ] || { echo "Keycloak administrator password file is unavailable" >&2; exit 1; }
     admin_password=$(cat "$admin_file")
     [ -n "$admin_password" ] || { echo "Keycloak administrator password file is empty" >&2; exit 1; }
     install -d -m 0750 "$state"
     install -d -m 0700 "$runtime"
     if [ ! -e "$ledger" ]; then
        printf '%s\n' '{"schema_version":3,"resources":{},"credentials":{"admin":null,"clients":{},"users":{},"federations":{}}}' > "$ledger"
       chown root:root "$ledger"
       chmod 0600 "$ledger"
     fi
      jq -e '(.schema_version == 2 or .schema_version == 3) and (.credentials | type == "object")' "$ledger" >/dev/null
      jq '.credentials.federations=(.credentials.federations // {})' "$ledger" > "$ledger.next"
      chmod 0600 "$ledger.next"; chown root:root "$ledger.next"; mv -f "$ledger.next" "$ledger"
     new_salt() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
     fingerprint() { printf '%s%s' "$1" "$2" | sha256sum | cut -d ' ' -f 1; }
     record_fingerprint() {
       kind=$1
       name=$2
       value=$3
       salt=$4
       fp=$(fingerprint "$salt" "$value")
       tmp=$(mktemp "$ledger.XXXXXX")
       if [ "$kind" = admin ]; then
         jq --arg salt "$salt" --arg fp "$fp" '.credentials.admin={salt:$salt,fingerprint:$fp,status:"applied"}' "$ledger" > "$tmp"
       else
         jq --arg kind "$kind" --arg name "$name" --arg salt "$salt" --arg fp "$fp" '.credentials[$kind][$name]={salt:$salt,fingerprint:$fp,status:"applied"}' "$ledger" > "$tmp"
       fi
       chmod 0600 "$tmp"; chown root:root "$tmp"; mv -f "$tmp" "$ledger"
     }
     admin_salt=$(jq -r '.credentials.admin.salt // empty' "$ledger")
     [ -n "$admin_salt" ] || admin_salt=$(new_salt)
     admin_fp=$(fingerprint "$admin_salt" "$admin_password")
     recorded_admin_fp=$(jq -r '.credentials.admin.fingerprint // empty' "$ledger")
     if [ -r "$admin_cache" ] && [ "$admin_fp" != "$recorded_admin_fp" ]; then
       old_admin_password=$(cat "$admin_cache")
       old_token=$(curl --fail --silent --show-error -u ${lib.escapeShellArg cfg.admin.username}:"$old_admin_password" \
         -H 'Content-Type: application/x-www-form-urlencoded' -d grant_type=password \
         -d client_id=admin-cli -d username=${lib.escapeShellArg cfg.admin.username} \
         --data-urlencode password="$old_admin_password" \
         "$api/realms/master/protocol/openid-connect/token" | jq -r .access_token) || {
           echo "Keycloak administrator replacement cannot be staged; prior credential remains active" >&2
           exit 1
         }
       admin_id=$(curl --fail --silent --show-error -H "Authorization: Bearer $old_token" "$api/admin/realms/master/users?username=${lib.escapeShellArg cfg.admin.username}" | jq -r '.[0].id')
       replacement_payload=$(jq -cn --arg value "$admin_password" '{type:"password",value:$value,temporary:false}')
       curl --fail --silent --show-error -H "Authorization: Bearer $old_token" -H 'Content-Type: application/json' \
         -X PUT "$api/admin/realms/master/users/$admin_id/reset-password" -d "$replacement_payload" >/dev/null || {
         echo "Keycloak administrator replacement was rejected; prior credential remains active" >&2
         exit 1
       }
     fi
     token=$(curl --fail --silent --show-error -u ${lib.escapeShellArg cfg.admin.username}:"$admin_password" \
       -H 'Content-Type: application/x-www-form-urlencoded' -d grant_type=password \
       -d client_id=admin-cli -d username=${lib.escapeShellArg cfg.admin.username} \
       --data-urlencode password="$admin_password" \
       "$api/realms/master/protocol/openid-connect/token" | jq -r .access_token) || true
     [ -n "$token" ] && [ "$token" != null ] || {
       if [ -r "$admin_cache" ] && [ "$admin_fp" != "$recorded_admin_fp" ]; then
         rollback_payload=$(jq -cn --arg value "$old_admin_password" '{type:"password",value:$value,temporary:false}')
         curl --fail --silent --show-error -H "Authorization: Bearer $old_token" -H 'Content-Type: application/json' \
           -X PUT "$api/admin/realms/master/users/$admin_id/reset-password" -d "$rollback_payload" >/dev/null || true
         echo "Keycloak administrator post-change authentication failed; prior credential may require operator recovery" >&2
       else
         echo "Keycloak administrator authentication failed" >&2
       fi
       exit 1
     }
     if [ "$admin_fp" != "$recorded_admin_fp" ]; then
       install -m 0400 -o root -g root "$admin_file" "$admin_cache"
       record_fingerprint admin admin "$admin_password" "$admin_salt"
     fi
    auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')
     api_get() { curl --fail --silent --show-error "''${auth[@]}" "$1"; }
     api_put() { curl --fail --silent --show-error "''${auth[@]}" -X PUT "$1" -d "$2" >/dev/null; }
      api_post() { curl --fail --silent --show-error "''${auth[@]}" -X POST "$1" -d "$2" >/dev/null; }
     ${lib.concatMapStringsSep "\n" (name: let federation = cfg.ldapFederations.${name}; in ''
       realm=${lib.escapeShellArg federation.realm}
       component_name=${lib.escapeShellArg federation.name}
       bind_password_file=${lib.escapeShellArg federation.bindPasswordFile}
       [ -r "$bind_password_file" ] || { echo "Keycloak federation bind password file is unavailable for ${lib.escapeShellArg name}" >&2; exit 1; }
       bind_password=$(cat "$bind_password_file")
       [ -n "$bind_password" ] || { echo "Keycloak federation bind password is empty for ${lib.escapeShellArg name}" >&2; exit 1; }
       components=$(api_get "$api/admin/realms/$realm/components?type=org.keycloak.storage.UserStorageProvider" 2>/dev/null || true)
       [ -n "$components" ] || components='[]'
       existing_component=$(jq -c --arg name "$component_name" '[.[] | select(.name == $name and .providerId == "ldap")] | if length == 1 then .[0] else empty end' <<<"$components")
       component_id=$(jq -r '.id // empty' <<<"$existing_component")
       if [ -n "$component_id" ]; then
         payload=$(jq --arg value "$bind_password" '.config.bindCredential=[$value]' <<<"$existing_component")
         api_put "$api/admin/realms/$realm/components/$component_id" "$payload"
       fi
     '') (lib.attrNames cfg.ldapFederations)}
     ${lib.concatMapStringsSep "\n" (name: let realm = cfg.realms.${name}; in ''
       payload=$(jq -cn --arg realm ${lib.escapeShellArg realm.name} --arg display ${lib.escapeShellArg realm.displayName} --argjson enabled ${lib.boolToString realm.enabled} '{realm:$realm,displayName:$display,enabled:$enabled,verifyEmail:false}')
      status=$(curl --silent --output /dev/null --write-out '%{http_code}' "''${auth[@]}" "$api/admin/realms/${realm.name}")
      case "$status" in
        200) curl --fail --silent --show-error "''${auth[@]}" -X PUT "$api/admin/realms/${realm.name}" -d "$payload" >/dev/null ;;
        404) curl --fail --silent --show-error "''${auth[@]}" -X POST "$api/admin/realms" -d "$payload" >/dev/null ;;
        *) echo "Unable to inspect Keycloak realm ${lib.escapeShellArg realm.name} (HTTP $status)" >&2; exit 1 ;;
      esac
    '') (lib.attrNames cfg.realms)}
    ${lib.concatMapStringsSep "\n" (name: let scope = cfg.clientScopes.${name}; in ''
      realm=${lib.escapeShellArg scope.realm}
      payload=$(jq -cn --arg name ${lib.escapeShellArg scope.name} --arg protocol ${lib.escapeShellArg scope.protocol} --argjson includeInTokenScope ${lib.boolToString scope.includeInTokenScope} '{name:$name,protocol:$protocol,includeInTokenScope:$includeInTokenScope}')
      existing=$(api_get "$api/admin/realms/$realm/client-scopes" | jq -c --arg name ${lib.escapeShellArg scope.name} '[.[] | select(.name == $name)] | if length == 1 then .[0] else empty end')
      if [ -z "$existing" ]; then api_post "$api/admin/realms/$realm/client-scopes" "$payload"; else api_put "$api/admin/realms/$realm/client-scopes/$(jq -r .id <<<"$existing")" "$payload"; fi
    '') (lib.attrNames cfg.clientScopes)}
    ${lib.concatMapStringsSep "\n" (name: let role = cfg.realmRoles.${name}; in ''
      realm=${lib.escapeShellArg role.realm}
      payload=$(jq -cn --arg name ${lib.escapeShellArg role.name} --arg description ${lib.escapeShellArg role.description} '{name:$name,description:$description}')
      existing=$(api_get "$api/admin/realms/$realm/roles/${lib.escapeShellArg role.name}" 2>/dev/null || true)
      if [ -z "$existing" ]; then api_post "$api/admin/realms/$realm/roles" "$payload"; else api_put "$api/admin/realms/$realm/roles/${role.name}" "$payload"; fi
    '') (lib.attrNames cfg.realmRoles)}
    ${lib.concatMapStringsSep "\n" (name: let role = cfg.clientRoles.${name}; in ''
      realm=${lib.escapeShellArg role.realm}
      client_id=$(api_get "$api/admin/realms/$realm/clients" | jq -r --arg id ${lib.escapeShellArg cfg.clients.${role.client}.clientId} '.[] | select(.clientId == $id) | .id' | head -n 1)
      [ -n "$client_id" ] || { echo "Keycloak client is missing for client role ${lib.escapeShellArg name}" >&2; exit 1; }
      payload=$(jq -cn --arg name ${lib.escapeShellArg role.name} --arg description ${lib.escapeShellArg role.description} '{name:$name,description:$description}')
      existing=$(api_get "$api/admin/realms/$realm/clients/$client_id/roles/${lib.escapeShellArg role.name}" 2>/dev/null || true)
      if [ -z "$existing" ]; then api_post "$api/admin/realms/$realm/clients/$client_id/roles" "$payload"; else api_put "$api/admin/realms/$realm/clients/$client_id/roles/${lib.escapeShellArg role.name}" "$payload"; fi
    '') (lib.attrNames cfg.clientRoles)}
    ${lib.concatMapStringsSep "\n" (name: let group = cfg.groups.${name}; in ''
      realm=${lib.escapeShellArg group.realm}
      payload=$(jq -cn --arg name ${lib.escapeShellArg group.name} '{name:$name}')
      existing=$(api_get "$api/admin/realms/$realm/groups" | jq -c --arg name ${lib.escapeShellArg group.name} '[.[] | select(.name == $name)] | if length == 1 then .[0] else empty end')
      if [ -z "$existing" ]; then api_post "$api/admin/realms/$realm/groups" "$payload"; fi
    '') (lib.attrNames cfg.groups)}
    ${lib.concatMapStringsSep "\n" (name: let client = cfg.clients.${name}; in ''
      realm=${lib.escapeShellArg client.realm}
       payload=$(jq -cn --arg clientId ${lib.escapeShellArg client.clientId} --argjson enabled ${lib.boolToString client.enabled} --argjson publicClient ${lib.boolToString client.public} --argjson redirectUris ${lib.escapeShellArg (builtins.toJSON client.redirectUris)} --argjson webOrigins ${lib.escapeShellArg (builtins.toJSON client.webOrigins)} --arg protocol ${lib.escapeShellArg client.protocol} --argjson consentRequired ${lib.boolToString client.consentRequired} --argjson standardFlowEnabled ${lib.boolToString (builtins.elem "authorization-code" client.flows)} --argjson directAccessGrantsEnabled ${lib.boolToString (builtins.elem "password" client.flows)} --argjson serviceAccountsEnabled ${lib.boolToString (!client.public)} '{clientId:$clientId,enabled:$enabled,publicClient:$publicClient,redirectUris:$redirectUris,webOrigins:$webOrigins,protocol:$protocol,consentRequired:$consentRequired,standardFlowEnabled:$standardFlowEnabled,directAccessGrantsEnabled:$directAccessGrantsEnabled,serviceAccountsEnabled:$serviceAccountsEnabled}')
       existing=$(api_get "$api/admin/realms/$realm/clients" | jq -c --arg id ${lib.escapeShellArg client.clientId} '[.[] | select(.clientId == $id)] | if length == 1 then .[0] else empty end')
        if [ -z "$existing" ]; then api_post "$api/admin/realms/$realm/clients" "$payload"; else api_put "$api/admin/realms/$realm/clients/$(jq -r .id <<<"$existing")" "$payload"; fi
        existing=$(api_get "$api/admin/realms/$realm/clients" | jq -c --arg id ${lib.escapeShellArg client.clientId} '[.[] | select(.clientId == $id)] | if length == 1 then .[0] else empty end')
        [ -n "$existing" ] || { echo "Keycloak client ${lib.escapeShellArg name} was not created" >&2; exit 1; }
        ${lib.optionalString client.includeGroupClaims ''
          client_id=$(jq -r .id <<<"$existing")
          mapper_name="${client.clientId}-groups"
          mapper_payload=$(jq -cn --arg name "$mapper_name" '{name:$name,protocol:"openid-connect",protocolMapper:"oidc-group-membership-mapper",config:{"claim.name":"groups","jsonType.label":"String","multivalued":"true","full.path":"true","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}')
          mapper_components=$(api_get "$api/admin/realms/$realm/clients/$client_id/protocol-mappers/models" 2>/dev/null || true)
          [ -n "$mapper_components" ] || mapper_components='[]'
          mapper_id=$(jq -r --arg name "$mapper_name" '[.[] | select(.name == $name)] | if length == 1 then .[0].id else empty end' <<<"$mapper_components")
          if [ -n "$mapper_id" ]; then
            mapper_payload=$(jq --arg id "$mapper_id" '. + {id:$id}' <<<"$mapper_payload")
            api_put "$api/admin/realms/$realm/clients/$client_id/protocol-mappers/models/$mapper_id" "$mapper_payload"
          else
            api_post "$api/admin/realms/$realm/clients/$client_id/protocol-mappers/models" "$mapper_payload"
          fi
        ''}
       ${lib.optionalString (!client.public) ''
         secret=$(cat ${lib.escapeShellArg client.secretFile})
         [ -n "$secret" ] || { echo "Keycloak client secret is empty for ${lib.escapeShellArg name}" >&2; exit 1; }
         client_cache="$runtime/client-${name}"
         client_salt=$(jq -r --arg name ${lib.escapeShellArg name} '.credentials.clients[$name].salt // empty' "$ledger")
         [ -n "$client_salt" ] || client_salt=$(new_salt)
         client_fp=$(fingerprint "$client_salt" "$secret")
         recorded_client_fp=$(jq -r --arg name ${lib.escapeShellArg name} '.credentials.clients[$name].fingerprint // empty' "$ledger")
         if [ "$client_fp" != "$recorded_client_fp" ]; then
           old_secret=
           [ -r "$client_cache" ] && old_secret=$(cat "$client_cache") || true
           secret_payload=$(jq -cn --arg secret "$secret" '{secret:$secret}')
           api_put "$api/admin/realms/$realm/clients/$(jq -r .id <<<"$existing")" "$secret_payload"
           client_token=$(curl --fail --silent --show-error -u ${lib.escapeShellArg client.clientId}:"$secret" \
             -H 'Content-Type: application/x-www-form-urlencoded' -d grant_type=client_credentials \
             "$api/realms/$realm/protocol/openid-connect/token" | jq -r .access_token) || true
           if [ -z "$client_token" ] || [ "$client_token" = null ]; then
             if [ -n "$old_secret" ]; then
               rollback_payload=$(jq -cn --arg secret "$old_secret" '{secret:$secret}')
               api_put "$api/admin/realms/$realm/clients/$(jq -r .id <<<"$existing")" "$rollback_payload" || true
             fi
             echo "Keycloak client secret replacement rejected for ${lib.escapeShellArg name}; prior credential remains active" >&2
             exit 1
           fi
           printf '%s' "$secret" > "$client_cache"; chmod 0400 "$client_cache"
           record_fingerprint clients ${lib.escapeShellArg name} "$secret" "$client_salt"
         fi
       ''}
    '') (lib.attrNames cfg.clients)}
    ${lib.concatMapStringsSep "\n" (name: let user = cfg.users.${name}; in ''
      realm=${lib.escapeShellArg user.realm}
      password=$(cat ${lib.escapeShellArg user.passwordFile})
      [ -n "$password" ] || { echo "Keycloak user password is empty for ${lib.escapeShellArg name}" >&2; exit 1; }
      payload=$(jq -cn --arg username ${lib.escapeShellArg user.username} --arg email ${lib.escapeShellArg user.email} --arg firstName ${lib.escapeShellArg user.firstName} --arg lastName ${lib.escapeShellArg user.lastName} --argjson enabled ${lib.boolToString user.enabled} --argjson emailVerified ${lib.boolToString user.emailVerified} --argjson requiredActions ${lib.escapeShellArg (builtins.toJSON user.requiredActions)} '{username:$username,email:$email,firstName:$firstName,lastName:$lastName,enabled:$enabled,emailVerified:$emailVerified,requiredActions:$requiredActions}')
      existing=$(api_get "$api/admin/realms/$realm/users" | jq -c --arg username ${lib.escapeShellArg user.username} '[.[] | select(.username == $username)] | if length == 1 then .[0] else empty end')
       if [ -z "$existing" ]; then api_post "$api/admin/realms/$realm/users" "$payload"; existing=$(api_get "$api/admin/realms/$realm/users" | jq -c --arg username ${lib.escapeShellArg user.username} '[.[] | select(.username == $username)] | .[0]'); else api_put "$api/admin/realms/$realm/users/$(jq -r .id <<<"$existing")" "$payload"; fi
       payload=$(jq -cn --argjson base "$payload" --arg value "$password" '$base + {credentials:[{type:"password",value:$value,temporary:false}]}')
       api_put "$api/admin/realms/$realm/users/$(jq -r .id <<<"$existing")" "$payload"
       user_cache="$runtime/user-${name}"
       user_salt=$(jq -r --arg name ${lib.escapeShellArg name} '.credentials.users[$name].salt // empty' "$ledger")
       [ -n "$user_salt" ] || user_salt=$(new_salt)
       user_fp=$(fingerprint "$user_salt" "$password")
       recorded_user_fp=$(jq -r --arg name ${lib.escapeShellArg name} '.credentials.users[$name].fingerprint // empty' "$ledger")
       if [ "$user_fp" != "$recorded_user_fp" ]; then
         old_password=
         [ -r "$user_cache" ] && old_password=$(cat "$user_cache") || true
         password_payload=$(jq -cn --arg value "$password" '{type:"password",value:$value,temporary:false}')
         api_put "$api/admin/realms/$realm/users/$(jq -r .id <<<"$existing")/reset-password" "$password_payload"
         ${lib.optionalString (passwordClient != null) ''
           if [ -r "$user_cache" ]; then
           user_token=$(curl --fail --silent --show-error \
             -H 'Content-Type: application/x-www-form-urlencoded' -d grant_type=password \
             -d client_id=${lib.escapeShellArg passwordClient.clientId} -d username=${lib.escapeShellArg user.username} --data-urlencode password="$password" -d scope=openid \
             "$api/realms/$realm/protocol/openid-connect/token" | jq -r .access_token) || true
           if [ -z "$user_token" ] || [ "$user_token" = null ]; then
             if [ -n "$old_password" ]; then
               rollback_payload=$(jq -cn --arg value "$old_password" '{type:"password",value:$value,temporary:false}')
               api_put "$api/admin/realms/$realm/users/$(jq -r .id <<<"$existing")/reset-password" "$rollback_payload" || true
             fi
             echo "Keycloak user password replacement rejected for ${lib.escapeShellArg name}; prior credential remains active" >&2
             exit 1
           fi
           fi
         ''}
         printf '%s' "$password" > "$user_cache"; chmod 0400 "$user_cache"
          record_fingerprint users ${lib.escapeShellArg name} "$password" "$user_salt"
        fi
       user_metadata=$(jq -cn --argjson requiredActions ${lib.escapeShellArg (builtins.toJSON user.requiredActions)} '{enabled:true,emailVerified:true,requiredActions:$requiredActions}')
       api_put "$api/admin/realms/$realm/users/$(jq -r .id <<<"$existing")" "$user_metadata"
       user_id=$(jq -r .id <<<"$existing")
      ${lib.concatMapStringsSep "\n" (groupName: ''
        group_id=$(api_get "$api/admin/realms/$realm/groups" | jq -r --arg name ${lib.escapeShellArg cfg.groups.${groupName}.name} '.[] | select(.name == $name) | .id' | head -n 1)
        [ -n "$group_id" ] || { echo "Keycloak group is missing for user ${lib.escapeShellArg name}" >&2; exit 1; }
        api_put "$api/admin/realms/$realm/users/$user_id/groups/$group_id" '{}'
      '') user.groups}
      ${lib.concatMapStringsSep "\n" (roleName: ''
        role_json=$(api_get "$api/admin/realms/$realm/roles/${lib.escapeShellArg cfg.realmRoles.${roleName}.name}")
        api_post "$api/admin/realms/$realm/users/$user_id/role-mappings/realm" "[$role_json]"
      '') user.realmRoles}
      '') (lib.attrNames cfg.users)}
     ${lib.concatMapStringsSep "\n" (name: let federation = cfg.ldapFederations.${name}; in ''
       realm=${lib.escapeShellArg federation.realm}
       component_name=${lib.escapeShellArg federation.name}
       bind_password_file=${lib.escapeShellArg federation.bindPasswordFile}
       trust_certificate_file=${lib.escapeShellArg federation.trustCertificateFile}
       [ -r "$bind_password_file" ] || { echo "Keycloak federation bind password file is unavailable for ${lib.escapeShellArg name}" >&2; exit 1; }
        [ -r "$trust_certificate_file" ] || { echo "Keycloak federation trust certificate is unavailable for ${lib.escapeShellArg name}" >&2; exit 1; }
        ${pkgs.openssl}/bin/openssl x509 -in "$trust_certificate_file" -noout >/dev/null || { echo "Keycloak federation trust certificate is invalid for ${lib.escapeShellArg name}" >&2; exit 1; }
        bind_password=$(cat "$bind_password_file")
        [ -n "$bind_password" ] || { echo "Keycloak federation bind password is empty for ${lib.escapeShellArg name}" >&2; exit 1; }
        bind_password_tmp=$(mktemp "$runtime/federation-password.XXXXXX")
        chmod 0400 "$bind_password_tmp"
        printf '%s' "$bind_password" > "$bind_password_tmp"
        LDAPTLS_CACERT="$trust_certificate_file" ldapsearch -x -H ${lib.escapeShellArg federation.connectionUrl} -D ${lib.escapeShellArg federation.bindDn} -y "$bind_password_tmp" -b ${lib.escapeShellArg federation.usersDn} -s base '(objectClass=*)' dn >/dev/null || {
          rm -f "$bind_password_tmp"
          echo "Keycloak federation bind credential or LDAPS trust validation failed for ${lib.escapeShellArg name}" >&2
          exit 1
        }
        rm -f "$bind_password_tmp"
       federation_record=$(jq -c --arg name ${lib.escapeShellArg name} '.resources.federations[$name] // empty' "$ledger")
       components=$(api_get "$api/admin/realms/$realm/components?type=org.keycloak.storage.UserStorageProvider")
       matches=$(jq -c --arg name "$component_name" '[.[] | select(.name == $name and .providerId == "ldap")]' <<<"$components")
       [ "$(jq length <<<"$matches")" != 2 ] || { echo "Keycloak federation identity is ambiguous: ${lib.escapeShellArg name}" >&2; exit 1; }
       if [ -z "$federation_record" ] && [ "$(jq length <<<"$matches")" = 1 ]; then
         echo "Keycloak federation collides with an unmanaged component: ${lib.escapeShellArg name}" >&2
         exit 1
       fi
       [ -n "$federation_record" ] && [ "$(jq -r '.providerId // empty' <<<"$federation_record")" = ldap ] || true
       component_id=$(jq -r '.[0].id // empty' <<<"$matches")
       realm_id=$(api_get "$api/admin/realms/$realm" | jq -r .id)
       payload=$(jq -cn \
          --arg name "$component_name" \
          --arg parent "$realm_id" \
         --arg url ${lib.escapeShellArg federation.connectionUrl} \
         --arg users_dn ${lib.escapeShellArg federation.usersDn} \
         --arg bind_dn ${lib.escapeShellArg federation.bindDn} \
         --arg trust_certificate "$trust_certificate_file" \
         --arg bind_credential "$bind_password" \
         --arg username_attr ${lib.escapeShellArg federation.usernameAttribute} \
         --arg group_attr ${lib.escapeShellArg federation.groupNameAttribute} \
         --arg membership_attr ${lib.escapeShellArg federation.membershipAttribute} \
         --argjson enabled true \
          '{name:$name,parentId:$parent,providerId:"ldap",providerType:"org.keycloak.storage.UserStorageProvider",config:{enabled:[$enabled|tostring],priority:["0"],connectionUrl:[$url],usersDn:[$users_dn],authType:["simple"],bindDn:[$bind_dn],bindCredential:[$bind_credential],editMode:["READ_ONLY"],usernameLDAPAttribute:[$username_attr],rdnLDAPAttribute:[$username_attr],uuidLDAPAttribute:["uid"],userObjectClasses:["inetOrgPerson","posixAccount"],searchScope:["1"],pagination:["true"],syncRegistrations:["false"],fullSyncPeriod:["-1"],changedSyncPeriod:["-1"],cachePolicy:["NO_CACHE"],useTruststoreSpi:["always"],groupNameLDAPAttribute:[$group_attr],membershipLDAPAttribute:[$membership_attr],membershipAttributeType:["DN"],groupObjectClasses:["groupOfNames"]}}')
        if [ -n "$component_id" ]; then
          update_payload=$(jq 'del(.parentId)' <<<"$payload")
          api_put "$api/admin/realms/$realm/components/$component_id" "$update_payload"
       else
         api_post "$api/admin/realms/$realm/components" "$payload"
         component_id=$(api_get "$api/admin/realms/$realm/components?type=org.keycloak.storage.UserStorageProvider" | jq -r --arg name "$component_name" '.[] | select(.name == $name and .providerId == "ldap") | .id' | head -n 1)
       fi
        [ -n "$component_id" ] || { echo "Keycloak federation was not created: ${lib.escapeShellArg name}" >&2; exit 1; }
        mapper_components=$(api_get "$api/admin/realms/$realm/components?type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" 2>/dev/null || true)
        [ -n "$mapper_components" ] || mapper_components='[]'
        mapper_name="''${component_name}-groups"
        mapper_payload=$(jq -cn \
          --arg name "$mapper_name" \
          --arg parent "$component_id" \
          --arg groups_dn ${lib.escapeShellArg federation.groupsDn} \
          --arg group_attr ${lib.escapeShellArg federation.groupNameAttribute} \
          --arg membership_attr ${lib.escapeShellArg federation.membershipAttribute} \
           '{name:$name,parentId:$parent,providerId:"group-ldap-mapper",providerType:"org.keycloak.storage.ldap.mappers.LDAPStorageMapper",config:{"groups.dn":[$groups_dn],"group.name.ldap.attribute":[$group_attr],"group.object.classes":["groupOfNames"],"membership.ldap.attribute":[$membership_attr],"membership.user.ldap.attribute":["uid"],"membership.attribute.type":["DN"],mode:["READ_ONLY"],"preserve.group.inheritance":["false"]}}')
        mapper_id=$(jq -r --arg name "$mapper_name" --arg parent "$component_id" '[.[] | select(.name == $name and .parentId == $parent and .providerId == "group-ldap-mapper")] | if length == 1 then .[0].id else empty end' <<<"$mapper_components")
         if [ -n "$mapper_id" ]; then api_put "$api/admin/realms/$realm/components/$mapper_id" "$mapper_payload"; else
           mapper_response=$(curl --silent --show-error --write-out '\n%{http_code}' "''${auth[@]}" -X POST "$api/admin/realms/$realm/components" -d "$mapper_payload")
           mapper_status=$(tail -n 1 <<<"$mapper_response")
           [ "$mapper_status" = 201 ] || { echo "Keycloak LDAP group mapper creation failed: $mapper_response" >&2; exit 1; }
         fi
         curl --fail --silent --show-error "''${auth[@]}" -X POST "$api/admin/realms/$realm/user-storage/$component_id/sync?action=triggerFullSync" >/dev/null
         federation_salt=$(jq -r --arg name ${lib.escapeShellArg name} '.credentials.federations[$name].salt // empty' "$ledger")
       [ -n "$federation_salt" ] || federation_salt=$(new_salt)
       federation_fp=$(fingerprint "$federation_salt" "$bind_password")
       recorded_federation_fp=$(jq -r --arg name ${lib.escapeShellArg name} '.credentials.federations[$name].fingerprint // empty' "$ledger")
       if [ "$federation_fp" != "$recorded_federation_fp" ]; then
         printf '%s' "$bind_password" > "$runtime/federation-${name}"
         chmod 0400 "$runtime/federation-${name}"
         record_fingerprint federations ${lib.escapeShellArg name} "$bind_password" "$federation_salt"
       fi
       jq --arg name ${lib.escapeShellArg name} --arg id "$component_id" '.resources.federations[$name]={id:$id,providerId:"ldap",status:"applied"}' "$ledger" > "$ledger.next"
       chmod 0600 "$ledger.next"; mv -f "$ledger.next" "$ledger"
     '') (lib.attrNames cfg.ldapFederations)}
     tmp=$(mktemp "$ledger.XXXXXX")
      jq --argjson desired "$(cat "$desired")" '.schema_version=3 | .resources=(.resources // {}) | .resources.desired=$desired | .resources.secret_values="excluded" | .resources.status="applied" | .credentials=(.credentials // {admin:null,clients:{},users:{},federations:{}}) | .credentials.federations=(.credentials.federations // {})' "$ledger" > "$tmp"
     chmod 0600 "$tmp"; chown root:root "$tmp"; mv "$tmp" "$ledger"
  '';
  observe = pkgs.writeShellScriptBin "osmium-keycloak-observe" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq ]}
    output=""
    case "''${1:-}" in --output) output=$2 ;; "") ;; *) echo "usage: osmium-keycloak-observe [--output FILE]" >&2; exit 2 ;; esac
    [ -s ${lib.escapeShellArg cfg.admin.passwordFile} ] || { echo "Keycloak administrator password file is unavailable" >&2; exit 2; }
    admin_password=$(cat ${lib.escapeShellArg cfg.admin.passwordFile})
    [ -n "$admin_password" ] || { echo "Keycloak administrator password file is empty" >&2; exit 2; }
    api=${lib.escapeShellArg "http://127.0.0.1:${toString cfg.httpPort}${cfg.httpPath}"}
    api=''${api%/}
    token=$(curl --fail --silent --show-error -u ${lib.escapeShellArg cfg.admin.username}:"$admin_password" \
      -H 'Content-Type: application/x-www-form-urlencoded' -d grant_type=password -d client_id=admin-cli \
      -d username=${lib.escapeShellArg cfg.admin.username} --data-urlencode password="$admin_password" \
      "$api/realms/master/protocol/openid-connect/token" | jq -r .access_token)
    [ -n "$token" ] && [ "$token" != null ] || { echo "Keycloak administrator authentication failed" >&2; exit 2; }
    auth=(-H "Authorization: Bearer $token")
    realms_json=$(curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms" | jq -cS '[.[] | {realm,enabled,displayName,sslRequired}] | sort_by(.realm)')
    clients_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms/$realm/clients" | jq -c --arg realm "$realm" '.[] | {realm:$realm,clientId,enabled,publicClient,protocol,redirectUris:(.redirectUris // [] | sort),webOrigins:(.webOrigins // [] | sort),standardFlowEnabled,directAccessGrantsEnabled,consentRequired}'; done | jq -sS 'sort_by([.realm,.clientId])')
    scopes_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms/$realm/client-scopes" | jq -c --arg realm "$realm" '.[] | {realm:$realm,name,protocol,attributes:(.attributes // {})}'; done | jq -sS 'sort_by([.realm,.name])')
    roles_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms/$realm/roles" | jq -c --arg realm "$realm" '.[] | {realm:$realm,name,description,composite}'; done | jq -sS 'sort_by([.realm,.name])')
    groups_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms/$realm/groups" | jq -c --arg realm "$realm" '.[] | {realm:$realm,id,name,path}'; done | jq -sS 'sort_by([.realm,.path])')
     users_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms/$realm/users" | jq -c --arg realm "$realm" '.[] | {realm:$realm,id,username,enabled,email,firstName,lastName,emailVerified,federationLink:(.federationLink != null)}'; done | jq -sS 'sort_by([.realm,.username])')
     keys_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/realms/$realm/protocol/openid-connect/certs" | jq -c --arg realm "$realm" '.keys[] | {realm:$realm,kid,kty,alg,use,crv,n,e,x,y}'; done | jq -sS 'sort_by([.realm,.kid])')
     ldap_json=$(for realm in $(jq -r '.[].realm' <<<"$realms_json"); do curl --fail --silent --show-error "''${auth[@]}" "$api/admin/realms/$realm/components?type=org.keycloak.storage.UserStorageProvider" | jq -c --arg realm "$realm" '.[] | select(.providerId == "ldap") | {realm:$realm,name,providerId,config:{enabled:(.config.enabled // []),connectionUrl:(.config.connectionUrl // []),usersDn:(.config.usersDn // []),bindDn:(.config.bindDn // []),usernameLDAPAttribute:(.config.usernameLDAPAttribute // []),groupNameLDAPAttribute:(.config.groupNameLDAPAttribute // []),membershipLDAPAttribute:(.config.membershipLDAPAttribute // []),useTruststoreSpi:(.config.useTruststoreSpi // []),editMode:(.config.editMode // [])},secrets:{bindPasswordFile:{unresolved:true},trustCertificateFile:{unresolved:true}}}'; done | jq -sS 'sort_by([.realm,.name])')
     report=$(jq -cnS --arg issuer ${lib.escapeShellArg cfg.issuer} --arg observed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --argjson realms "$realms_json" --argjson clients "$clients_json" --argjson scopes "$scopes_json" --argjson roles "$roles_json" --argjson groups "$groups_json" --argjson users "$users_json" --argjson keys "$keys_json" --argjson ldapFederations "$ldap_json" \
       '{schema_version:2,source:{origin:"runtime-observation",method:"keycloak-admin-api",review_only:true},provenance:{observed_fields:["realms","clients","users","ldapFederations"],secret_policy:"secret-bytes-excluded"},observed_at:$observed_at,issuer:$issuer,complete:false,activation_ready:false,realms:$realms,clients:$clients,clientScopes:$scopes,realmRoles:$roles,groups:$groups,users:$users,keys:$keys,ldapFederations:$ldapFederations,lldapGateway:{unresolved:true,reason:"gateway-is-observed-by-lldap-runtime"},secrets:{excluded:true,unresolved:["admin.passwordFile","clients.*.secretFile","users.*.passwordFile","ldapFederations.*.bindPasswordFile","ldapFederations.*.trustCertificateFile","signingKeys.*.privateKeyFile","lldapGateway.*"]},findings:["secret-file-reference-required","federated-and-external-users-unresolved","lldap-gateway-metadata-requires-lldap-observation"]}')
    if [ -n "$output" ]; then install -d -m 0750 "$(dirname "$output")"; printf '%s\n' "$report" > "$output"; else printf '%s\n' "$report"; fi
  '';
  candidate = pkgs.writeShellScriptBin "osmium-keycloak-candidate" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.jq ]}
    [ "''${1:-}" = "--input" ] && [ -r "''${2:-}" ] || { echo "usage: osmium-keycloak-candidate --input OBSERVATION" >&2; exit 2; }
    jq -cS '
      def key($prefix; $value): ($prefix + "_" + ($value | ascii_downcase | gsub("[^a-z0-9]+"; "_") | gsub("^_+|_+$"; "")));
      . as $o |
      ($o.realms | map({key:(.realm | gsub("[^A-Za-z0-9._-]"; "_")),value:{name:.realm,enabled:.enabled,displayName:(.displayName // .realm)}}) | from_entries) as $realms |
      ($o.clients | map({key:key("client"; (.realm + "_" + .clientId)),value:{realm:.realm,clientId:.clientId,enabled:.enabled,public:.publicClient,protocol:.protocol,redirectUris:.redirectUris,webOrigins:.webOrigins,secretFile:{unresolved:true}}}) | from_entries) as $clients |
       ($o.users | map({key:key("user"; (.realm + "_" + (.username // ""))),value:{realm:.realm,username:.username,enabled:.enabled,email:(.email // ""),firstName:(.firstName // ""),lastName:(.lastName // ""),passwordFile:{unresolved:true}}}) | from_entries) as $users |
        ($o.ldapFederations | map({key:key("ldap"; (.realm + "_" + .name)),value:{realm:.realm,name:.name,directory:"lldap",connectionUrl:(.config.connectionUrl[0] // ""),usersDn:(.config.usersDn[0] // ""),groupsDn:(.config.groupsDn[0] // ""),bindDn:(.config.bindDn[0] // ""),usernameAttribute:(.config.usernameLDAPAttribute[0] // "uid"),groupNameAttribute:(.config.groupNameLDAPAttribute[0] // "cn"),membershipAttribute:(.config.membershipLDAPAttribute[0] // "member"),bindPasswordFile:{unresolved:true},trustCertificateFile:{unresolved:true}}}) | from_entries) as $ldap |
       {schema_version:1,complete:false,activation_ready:false,
       provenance:(($o.source // {}) + {conversion:"review-only",observed_at:$o.observed_at}),
       declaration:{services:{osmium:{keycloak:{issuer:($o.issuer),realms:$realms,clients:$clients,users:$users,ldapFederations:$ldap}}}},
       secrets:{excluded:true},unresolved:["admin.passwordFile","clients.*.secretFile","users.*.passwordFile","signingKeys.*.privateKeyFile"],
       findings:(($o.findings // []) + ["operator_review_required","lldap-gateway-metadata-unresolved"] + (if any($o.users[]?; .federationLink == true) then ["federated-user-state-unsupported"] else [] end))}' "$2"
  '';
in
{
  options.services.osmium.keycloak = {
    enable = lib.mkEnableOption "the native Osmium Keycloak service";
    package = lib.mkPackageOption pkgs "keycloak" { };
    stateDir = lib.mkOption { type = lib.types.str; default = "/var/lib/keycloak"; description = "Persistent Keycloak and reconciliation state."; };
    issuer = lib.mkOption { type = lib.types.str; default = "https://keycloak.example.invalid"; description = "Externally advertised issuer URL."; };
    httpPath = lib.mkOption { type = lib.types.strMatching "/[A-Za-z0-9._/-]*"; default = "/"; description = "Keycloak HTTP relative path."; };
    httpPort = lib.mkOption { type = lib.types.port; default = 8080; description = "Guest HTTP port."; };
    httpsPort = lib.mkOption { type = lib.types.port; default = 8443; description = "Guest HTTPS port."; };
    hostHttpPort = lib.mkOption { type = lib.types.port; default = 8080; description = "Forwarded HTTP port."; };
    hostHttpsPort = lib.mkOption { type = lib.types.port; default = 8443; description = "Forwarded HTTPS port."; };
    allowInsecureHttp = lib.mkOption { type = lib.types.bool; default = false; description = "Allow HTTP for isolated tests only."; };
    tls = {
      certificateFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Runtime TLS certificate file."; };
      keyFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Runtime TLS private-key file."; };
    };
    database = {
      passwordFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Runtime PostgreSQL password file."; };
      name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9_]+"; default = "keycloak"; description = "Local database name."; };
      user = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9_]+"; default = "keycloak"; description = "Local database user."; };
    };
    admin = {
      username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "admin"; description = "Runtime administrator username."; };
      passwordFile = lib.mkOption { type = lib.types.str; description = "Runtime administrator password file."; };
    };
    realms = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = name; description = "Stable realm name."; };
          enabled = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the realm accepts logins."; };
          displayName = lib.mkOption { type = lib.types.str; default = name; description = "Realm display name."; };
        };
      }));
      default = { };
      description = "Declarative Keycloak realms.";
    };
    clientScopes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = name; description = "Client-scope name."; };
          protocol = lib.mkOption { type = lib.types.enum [ "openid-connect" "saml" ]; default = "openid-connect"; description = "Client-scope protocol."; };
          includeInTokenScope = lib.mkOption { type = lib.types.bool; default = true; description = "Include this scope in token scope claims."; };
        };
      }));
      default = { };
      description = "Declarative Keycloak client scopes.";
    };
    realmRoles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = name; description = "Realm role name."; };
          description = lib.mkOption { type = lib.types.str; default = ""; description = "Realm role description."; };
        };
      }));
      default = { };
      description = "Declarative Keycloak realm roles.";
    };
    clientRoles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          client = lib.mkOption { type = lib.types.str; description = "Declared client key."; };
          name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = name; description = "Client role name."; };
          description = lib.mkOption { type = lib.types.str; default = ""; description = "Client role description."; };
        };
      }));
      default = { };
      description = "Declarative Keycloak client roles.";
    };
    groups = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = name; description = "Group name."; };
          realmRoles = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Realm roles assigned to the group."; };
        };
      }));
      default = { };
      description = "Declarative Keycloak groups.";
    };
    clients = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          clientId = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._:-]+"; description = "OIDC client ID."; };
          enabled = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the client is enabled."; };
          public = lib.mkOption { type = lib.types.bool; default = false; description = "Whether the client is public."; };
          redirectUris = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Exact OIDC callback URLs."; };
          webOrigins = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Allowed browser origins."; };
          secretFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Runtime confidential-client secret file."; };
          protocol = lib.mkOption { type = lib.types.enum [ "openid-connect" "saml" ]; default = "openid-connect"; description = "Client protocol."; };
          flows = lib.mkOption { type = lib.types.listOf (lib.types.enum [ "authorization-code" "password" ]); default = [ "authorization-code" ]; description = "Supported authentication flows."; };
          consentRequired = lib.mkOption { type = lib.types.bool; default = false; description = "Require user consent."; };
           scopes = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Assigned client scopes."; };
           includeGroupClaims = lib.mkOption { type = lib.types.bool; default = false; description = "Include federated and local group paths in OIDC tokens."; };
          realmRoles = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Realm roles assigned to the client."; };
          clientRoles = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Client roles assigned to the client."; };
        };
      }));
      default = { };
      description = "Declarative OIDC clients.";
    };
    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; description = "Stable username."; };
          enabled = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the user is enabled."; };
          email = lib.mkOption { type = lib.types.str; default = ""; description = "User email claim."; };
          passwordFile = lib.mkOption { type = lib.types.str; description = "Runtime user password file."; };
          firstName = lib.mkOption { type = lib.types.str; default = ""; description = "User first name."; };
          lastName = lib.mkOption { type = lib.types.str; default = ""; description = "User last name."; };
          emailVerified = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the email claim is verified."; };
          requiredActions = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Keycloak required actions."; };
          groups = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Declared group keys."; };
          realmRoles = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Declared realm role names."; };
        };
      }));
      default = { };
      description = "Declarative local users.";
    };
    ldapFederations = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = name; description = "Stable Keycloak LDAP provider name."; };
          realm = lib.mkOption { type = lib.types.str; description = "Declared realm key."; };
          directory = lib.mkOption { type = lib.types.enum [ "lldap" ]; default = "lldap"; description = "Managed directory reference."; };
          connectionUrl = lib.mkOption { type = lib.types.strMatching "ldaps://[^[:space:]]+"; description = "Verified LDAPS endpoint."; };
           usersDn = lib.mkOption { type = lib.types.strMatching "ou=[A-Za-z0-9._-]+,dc=[A-Za-z0-9._=-]+(,dc=[A-Za-z0-9._=-]+)*"; description = "LDAP users search base."; };
           groupsDn = lib.mkOption { type = lib.types.strMatching "ou=[A-Za-z0-9._-]+,dc=[A-Za-z0-9._=-]+(,dc=[A-Za-z0-9._=-]+)*"; description = "LDAP groups search base for the managed group mapper."; };
          bindDn = lib.mkOption { type = lib.types.strMatching "uid=[A-Za-z0-9._-]+,ou=people,dc=[A-Za-z0-9._=-]+(,dc=[A-Za-z0-9._=-]+)*"; description = "Dedicated LDAP bind DN."; };
          bindUser = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; description = "LLDAP consumer bind-user declaration key."; };
          bindPasswordFile = lib.mkOption { type = lib.types.path; description = "Runtime bind-password file."; };
          trustCertificateFile = lib.mkOption { type = lib.types.path; description = "Runtime CA certificate used to trust LDAPS."; };
          usernameAttribute = lib.mkOption { type = lib.types.enum [ "uid" ]; default = "uid"; description = "Supported LDAP username attribute."; };
          groupNameAttribute = lib.mkOption { type = lib.types.enum [ "cn" ]; default = "cn"; description = "Supported LDAP group-name attribute."; };
          membershipAttribute = lib.mkOption { type = lib.types.enum [ "member" ]; default = "member"; description = "Supported LDAP group membership attribute."; };
        };
      }));
      default = { };
      description = "Managed LLDAP federation providers, one per realm.";
    };
    reverseConfiguration.enable = lib.mkEnableOption "review-only Keycloak observation tooling";
    removalPolicy = lib.mkOption { type = lib.types.enum [ "retain" "disable" "delete" ]; default = "retain"; description = "Default policy for managed resources removed from declarations."; };
    signingKeys = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; description = "Public metadata for signing-key declarations; private material is not evaluated."; };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = lib.hasPrefix "/var/lib/" cfg.stateDir; message = "services.osmium.keycloak.stateDir must be below /var/lib."; }
      { assertion = lib.hasPrefix "https://" cfg.issuer || lib.hasPrefix "http://" cfg.issuer; message = "Keycloak issuer must be an absolute HTTP(S) URL."; }
      { assertion = cfg.allowInsecureHttp || lib.hasPrefix "https://" cfg.issuer; message = "Keycloak production issuer must use HTTPS; allowInsecureHttp is test-only."; }
      { assertion = (cfg.tls.certificateFile == null) == (cfg.tls.keyFile == null); message = "Keycloak TLS certificateFile and keyFile must be provided together."; }
      { assertion = lib.all (client: client.public || client.secretFile != null) clients; message = "Every confidential Keycloak client requires a runtime secretFile."; }
      { assertion = lib.all (client: builtins.hasAttr client.realm cfg.realms) clients; message = "Keycloak clients must reference declared realms."; }
      { assertion = lib.all (user: builtins.hasAttr user.realm cfg.realms) users; message = "Keycloak users must reference declared realms."; }
      { assertion = lib.all (scope: builtins.hasAttr scope.realm cfg.realms) clientScopes; message = "Keycloak client scopes must reference declared realms."; }
      { assertion = lib.all (role: builtins.hasAttr role.realm cfg.realms) realmRoles; message = "Keycloak realm roles must reference declared realms."; }
      { assertion = lib.all (role: builtins.hasAttr role.realm cfg.realms && builtins.hasAttr role.client cfg.clients) clientRoles; message = "Keycloak client roles must reference declared realms and clients."; }
      { assertion = lib.all (group: builtins.hasAttr group.realm cfg.realms && lib.all (role: builtins.hasAttr role cfg.realmRoles) group.realmRoles) groups; message = "Keycloak groups must reference declared realms and realm roles."; }
      { assertion = lib.all (user: lib.all (group: builtins.hasAttr group cfg.groups) user.groups && lib.all (role: builtins.hasAttr role cfg.realmRoles) user.realmRoles) users; message = "Keycloak user mappings must reference declared groups and realm roles."; }
      { assertion = lib.all (federation: builtins.hasAttr federation.realm cfg.realms) ldapFederations; message = "Keycloak LDAP federations must reference declared realms."; }
      { assertion = lib.length (lib.unique (map (federation: federation.realm) ldapFederations)) == lib.length ldapFederations; message = "Only one managed LLDAP federation is allowed per realm."; }
      { assertion = lib.all (federation: federation.directory == "lldap" && config.services.osmium.lldap.enable) ldapFederations; message = "Keycloak LDAP federation requires the managed LLDAP service."; }
      { assertion = lib.all (federation: federation.trustCertificateFile != federation.bindPasswordFile && !lib.hasPrefix "/nix/store/" (toString federation.trustCertificateFile) && !lib.hasPrefix "/nix/store/" (toString federation.bindPasswordFile)) ldapFederations; message = "Keycloak LDAP trust and bind inputs must be distinct runtime files outside the Nix store."; }
      { assertion = lib.all (federation: builtins.hasAttr federation.bindUser config.services.osmium.lldap.users && config.services.osmium.lldap.users.${federation.bindUser}.consumer == "keycloak") ldapFederations; message = "Keycloak LDAP federations must reference a dedicated keycloak consumer bind user."; }
      { assertion = lib.all (federation: builtins.hasAttr federation.bindUser config.services.osmium.lldap.users && federation.bindDn == "uid=${config.services.osmium.lldap.users.${federation.bindUser}.username},ou=people,${config.services.osmium.lldap.baseDn}") ldapFederations; message = "Keycloak LDAP bindDn must match the referenced managed LLDAP consumer user."; }
      { assertion = lib.all (federation: config.services.osmium.lldap.ldaps.enable && lib.hasPrefix "ldaps://" federation.connectionUrl) ldapFederations; message = "Keycloak LDAP federation only permits verified LDAPS endpoints."; }
      { assertion = lib.all (client: client.protocol == "openid-connect") clients; message = "Only OpenID Connect clients are supported by Osmium Keycloak."; }
      { assertion = lib.all (client: lib.all (uri: !(lib.hasInfix "*" uri)) client.redirectUris) clients; message = "Keycloak redirect URIs must not contain wildcards."; }
      { assertion = lib.all (client: client.public || client.secretFile != null) clients; message = "Every confidential Keycloak client requires a runtime secretFile."; }
      { assertion = lib.length (lib.unique (map (realm: realm.name) realms)) == lib.length realms; message = "Keycloak realm names must be unique."; }
      { assertion = lib.length (lib.unique (map (client: "${client.realm}:${client.clientId}") clients)) == lib.length clients; message = "Keycloak client identities must be unique per realm."; }
      { assertion = lib.all (client: lib.all (uri: lib.hasPrefix "https://" uri || cfg.allowInsecureHttp) client.redirectUris) clients; message = "Keycloak redirect URIs must use HTTPS outside isolated tests."; }
      { assertion = cfg.hostHttpPort != cfg.hostHttpsPort; message = "Keycloak host HTTP and HTTPS ports must differ."; }
    ];
    services.keycloak = {
      enable = true;
      package = cfg.package;
      database = { createLocally = true; type = "postgresql"; name = cfg.database.name; username = cfg.database.user; passwordFile = cfg.database.passwordFile; };
      settings = {
        http-enabled = cfg.allowInsecureHttp;
        http-port = cfg.httpPort;
        http-relative-path = cfg.httpPath;
        hostname = cfg.issuer;
      } // lib.optionalAttrs (ldapFederations != [ ]) {
        truststore-paths = lib.concatStringsSep "," (map (federation: federation.trustCertificateFile) ldapFederations);
      };
    };
    systemd.services.osmium-keycloak-bootstrap-env = {
      description = "Prepare the runtime-only Keycloak bootstrap environment";
      wantedBy = [ "multi-user.target" ];
      before = [ "keycloak.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "osmium-keycloak-bootstrap-env" ''
          set -eu
          password_file=${lib.escapeShellArg cfg.admin.passwordFile}
          [ -s "$password_file" ] || { echo "Keycloak administrator password file is unavailable" >&2; exit 1; }
          install -d -m 0700 /run/osmium-keycloak
          temporary=$(mktemp /run/osmium-keycloak/bootstrap.env.XXXXXX)
          printf 'KC_BOOTSTRAP_ADMIN_USERNAME=%s\nKC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' ${lib.escapeShellArg cfg.admin.username} "$(cat "$password_file")" > "$temporary"
          chmod 0400 "$temporary"
          mv -f "$temporary" /run/osmium-keycloak/bootstrap.env
        '';
      };
    };
    systemd.services.keycloak = {
      after = [ "osmium-keycloak-bootstrap-env.service" ];
      requires = [ "osmium-keycloak-bootstrap-env.service" ];
      serviceConfig.EnvironmentFile = "/run/osmium-keycloak/bootstrap.env";
    };
    environment.systemPackages = lib.optional cfg.reverseConfiguration.enable observe ++ lib.optional cfg.reverseConfiguration.enable candidate;
    environment.persistence."/persistent" = { directories = [{ directory = stateDir; mode = "0750"; }]; };
    systemd.services.osmium-keycloak-reconcile = {
      description = "Reconcile declarative Osmium Keycloak state";
      wantedBy = [ "multi-user.target" ];
      after = [ "keycloak.service" ] ++ lib.optional (ldapFederations != [ ]) "osmium-lldap-reconcile.service";
      requires = [ "keycloak.service" ] ++ lib.optional (ldapFederations != [ ]) "osmium-lldap-reconcile.service";
      path = [ pkgs.curl pkgs.jq pkgs.coreutils ];
      serviceConfig = { Type = "oneshot"; User = "root"; RemainAfterExit = true; ExecStart = reconciler; };
    };
     systemd.paths.osmium-keycloak-reconcile = { wantedBy = [ "multi-user.target" ]; pathConfig = { PathChanged = [ cfg.admin.passwordFile ] ++ lib.concatMap (client: lib.optional (!client.public) client.secretFile) clients ++ map (user: user.passwordFile) users ++ lib.concatMap (federation: [ federation.bindPasswordFile federation.trustCertificateFile ]) ldapFederations; Unit = "osmium-keycloak-reconcile.service"; }; };
  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = [{ from = "host"; proto = "tcp"; host.port = cfg.hostHttpPort; guest.port = cfg.httpPort; }];
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];
  });
}
