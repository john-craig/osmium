{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.gotify;
  users = lib.attrValues cfg.users;
  applications = lib.attrValues cfg.applications;
  stateDir = cfg.stateDir;
  ledger = "${stateDir}/.osmium-ledger.json";
  bootstrapMarker = "${stateDir}/.osmium-admin-bootstrap-complete";
  adminPassword = cfg.admin.passwordFile;
  enabledUsers = cfg.users != { } || cfg.applications != { };

  wrapper = pkgs.writeShellScript "osmium-gotify-server" ''
    set -eu
    password_file=${lib.escapeShellArg (if cfg.admin.passwordFile == null then "/dev/null" else cfg.admin.passwordFile)}
    if [ -s "$password_file" ]; then
      export GOTIFY_DEFAULTUSER_NAME=${lib.escapeShellArg cfg.admin.username}
      export GOTIFY_DEFAULTUSER_PASS="$(cat "$password_file")"
    fi
    exec ${cfg.package}/bin/server
  '';

  reconcile = pkgs.writeShellScript "osmium-gotify-reconcile" ''
    set -eu
    api="http://127.0.0.1:${toString cfg.httpPort}"
    admin_name=${lib.escapeShellArg cfg.admin.username}
    admin_password_file=${lib.escapeShellArg (if adminPassword == null then "/dev/null" else adminPassword)}
    state=${lib.escapeShellArg stateDir}
    ledger=${lib.escapeShellArg ledger}

    [ -s "$admin_password_file" ] || { echo "Gotify administrator password file is empty or unavailable" >&2; exit 1; }
    admin_password=$(cat "$admin_password_file")
    auth() {
      printf '%s:%s' "$1" "$2"
    }
    admin_token=$(auth "$admin_name" "$admin_password")
    [ -n "$admin_token" ] || { echo "Gotify administrator authentication failed" >&2; exit 1; }
    bearer() { curl --fail --silent --show-error -u "$1" "$2"; }
    json_post() { curl --fail --silent --show-error -u "$1" -H 'Content-Type: application/json' -X POST "$2" -d @-; }
    json_put() { curl --fail --silent --show-error -u "$1" -H 'Content-Type: application/json' -X PUT "$2" -d @-; }
    json_delete() { curl --fail --silent --show-error -u "$1" -X DELETE "$2"; }
    declared_applications=${lib.escapeShellArg (builtins.toJSON (lib.attrNames cfg.applications))}
    declared_users=${lib.escapeShellArg (builtins.toJSON (lib.attrNames cfg.users))}

    [ -e "$ledger" ] || printf '%s\n' '{"schema_version":1,"users":[],"applications":[]}' > "$ledger"
    jq -e '.schema_version == 1 and (.users|type == "array") and (.applications|type == "array")' "$ledger" >/dev/null

    ${lib.concatMapStringsSep "\n" (name:
      let user = cfg.users.${name};
      in ''
      user_password=$(cat ${lib.escapeShellArg user.passwordFile})
      [ -n "$user_password" ] || { echo "Gotify user password is empty: ${lib.escapeShellArg user.username}" >&2; exit 1; }
      users_json=$(bearer "$admin_token" "$api/user")
      user_id=$(jq -r --arg name ${lib.escapeShellArg user.username} '[.[] | select(.name == $name)] | if length == 1 then .[0].id else empty end' <<<"$users_json")
      if [ -z "$user_id" ]; then
        printf '%s' "$(jq -cn --arg name ${lib.escapeShellArg user.username} --arg pass "$user_password" '{name:$name,pass:$pass,admin:false}')" |
          json_post "$admin_token" "$api/user" >/dev/null
        users_json=$(bearer "$admin_token" "$api/user")
        user_id=$(jq -r --arg name ${lib.escapeShellArg user.username} '[.[] | select(.name == $name)] | .[0].id' <<<"$users_json")
      else
        current=$(jq -r --arg name ${lib.escapeShellArg user.username} '[.[] | select(.name == $name)] | .[0].admin' <<<"$users_json")
        [ "$current" = "false" ] || { echo "Gotify declared user is an administrator: ${lib.escapeShellArg user.username}" >&2; exit 1; }
      fi
      user_record=$(jq -c --arg declaration ${lib.escapeShellArg name} '.users[] | select(.declaration == $declaration)' "$ledger" || true)
      if [ -z "$user_record" ]; then
        password_salt=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
        password_digest=$(printf '%s:%s' "$password_salt" "$user_password" | sha256sum | cut -d' ' -f1)
      else
        password_salt=$(jq -r '.password_salt // empty' <<<"$user_record")
        password_digest=$(jq -r '.password_digest // empty' <<<"$user_record")
        if [ -z "$password_salt" ] || [ -z "$password_digest" ]; then
          echo "Gotify password rotation state is incomplete for ${lib.escapeShellArg user.username}" >&2
          exit 1
        fi
        current_digest=$(printf '%s:%s' "$password_salt" "$user_password" | sha256sum | cut -d' ' -f1)
        if [ "$current_digest" != "$password_digest" ]; then
          printf '%s' "$(jq -cn --arg name ${lib.escapeShellArg user.username} --arg pass "$user_password" '{name:$name,pass:$pass,admin:false}')" |
            json_post "$admin_token" "$api/user/$user_id" >/dev/null
          password_digest=$current_digest
        fi
      fi
      user_token=$(auth ${lib.escapeShellArg user.username} "$user_password")
      [ -n "$user_token" ] || { echo "Unable to authenticate declared Gotify user" >&2; exit 1; }
      stale_apps=$(jq -c --arg owner ${lib.escapeShellArg name} --argjson declared "$declared_applications" '[.applications[] as $app | select($app.owner == $owner and (($declared | index($app.declaration)) == null)) | $app]' "$ledger")
      while IFS= read -r stale_app; do
        [ -n "$stale_app" ] || continue
        stale_id=$(jq -r '.id // empty' <<<"$stale_app")
        stale_name=$(jq -r '.name // empty' <<<"$stale_app")
        stale_output=$(jq -r '.output // empty' <<<"$stale_app")
        [ -n "$stale_id" ] && [ -n "$stale_name" ] && [ -n "$stale_output" ] || {
          echo "Gotify managed application cleanup state is incomplete for ${lib.escapeShellArg name}: id=$stale_id name=$stale_name output=$stale_output" >&2
          exit 1
        }
        current_stale=$(bearer "$user_token" "$api/application")
        match_count=$(jq -r --arg id "$stale_id" --arg name "$stale_name" '[.[] | select((.id|tostring) == $id and .name == $name)] | length' <<<"$current_stale")
        [ "$match_count" = 1 ] || {
          echo "Gotify managed application cleanup identity could not be proven: ${lib.escapeShellArg name}/$stale_name" >&2
          exit 1
        }
        json_delete "$user_token" "$api/application/$stale_id" >/dev/null
        if [ -L "$stale_output" ]; then
          echo "Gotify managed application cleanup refuses symlink output: $stale_output" >&2
          exit 1
        fi
        rm -f -- "$stale_output"
        jq --arg declaration "$(jq -r '.declaration' <<<"$stale_app")" '.applications = [.applications[] | select(.declaration != $declaration)]' "$ledger" > "$ledger.next"
        mv "$ledger.next" "$ledger"
      done < <(jq -c '.[]' <<<"$stale_apps")
      ${lib.concatMapStringsSep "\n" (appName:
        let app = cfg.applications.${appName};
        in lib.optionalString (app.owner == name) ''
        apps=$(bearer "$user_token" "$api/application")
        app_json=$(jq -c --arg name ${lib.escapeShellArg app.name} '[.[] | select(.name == $name)] | if length == 1 then .[0] else empty end' <<<"$apps")
        app_id=$(jq -r '.id // empty' <<<"$app_json")
        if [ -z "$app_id" ]; then
          app_json=$(printf '%s' "$(jq -cn --arg name ${lib.escapeShellArg app.name} --arg description ${lib.escapeShellArg app.description} '{name:$name,description:$description}')" | json_post "$user_token" "$api/application")
          app_id=$(jq -r '.id // empty' <<<"$app_json")
          app_token=$(jq -r '.token // empty' <<<"$app_json")
          [ -n "$app_token" ] || { echo "Gotify did not return an application token" >&2; exit 1; }
          install -d -m 0750 "$(dirname ${lib.escapeShellArg app.output.secretPath})"
          umask 0077
          tmp=$(mktemp ${lib.escapeShellArg app.output.secretPath}.XXXXXX)
          printf '%s\n' "$app_token" > "$tmp"
          chown ${lib.escapeShellArg "${app.output.owner}:${app.output.group}"} "$tmp"
          chmod ${lib.escapeShellArg app.output.mode} "$tmp"
          mv "$tmp" ${lib.escapeShellArg app.output.secretPath}
        else
          [ -s ${lib.escapeShellArg app.output.secretPath} ] || { echo "Gotify application token output is missing: ${lib.escapeShellArg app.output.secretPath}" >&2; exit 1; }
        fi
        printf '%s' "$(jq -cn --arg name ${lib.escapeShellArg app.name} --arg description ${lib.escapeShellArg app.description} '{name:$name,description:$description}')" |
          json_put "$user_token" "$api/application/$app_id" >/dev/null
        jq --arg declaration ${lib.escapeShellArg appName} --arg owner ${lib.escapeShellArg app.owner} --arg name ${lib.escapeShellArg app.name} --arg description ${lib.escapeShellArg app.description} --arg id "$app_id" --arg output ${lib.escapeShellArg app.output.secretPath} '.applications = ([.applications[] | select(.declaration != $declaration)] + [{declaration:$declaration,owner:$owner,name:$name,description:$description,id:($id|tonumber),output:$output,status:"success"}])' "$ledger" > "$ledger.next"
        mv "$ledger.next" "$ledger"
      '') (lib.attrNames cfg.applications)}
      jq --arg declaration ${lib.escapeShellArg name} --arg username ${lib.escapeShellArg user.username} --arg id "$user_id" --arg salt "$password_salt" --arg digest "$password_digest" '.users = ([.users[] | select(.declaration != $declaration)] + [{declaration:$declaration,username:$username,id:($id|tonumber),admin:false,password_salt:$salt,password_digest:$digest,status:"success"}])' "$ledger" > "$ledger.next"
      mv "$ledger.next" "$ledger"

    '') (lib.attrNames cfg.users)}

    stale_users=$(jq -c --argjson declared "$declared_users" '[.users[] as $user | select(($declared | index($user.declaration)) == null) | $user]' "$ledger")
    while IFS= read -r stale_user; do
      [ -n "$stale_user" ] || continue
      stale_username=$(jq -r '.username // empty' <<<"$stale_user")
      echo "Gotify managed user removal for $stale_username is unresolved: password-backed ownership proof is unavailable" >&2
      exit 1
    done < <(jq -c '.[]' <<<"$stale_users")
    chmod 0640 "$ledger"
  '';

  reverseTool = pkgs.writeShellScriptBin "osmium-gotify" ''
    set -eu
    command=''${1:-capture}
    input=""
    output=""
    extra_user=""
    extra_password_file=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        capture|drift|convert|export) command=$1 ;;
        --input) shift; input=$1 ;;
        --output) shift; output=$1 ;;
        --credential) shift; extra_user=''${1%%:*}; extra_password_file=''${1#*:} ;;
        --json) ;;
        *) echo "usage: osmium-gotify {capture|drift|convert|export} [--input FILE] [--output FILE] [--credential USER:PASSWORD_FILE]" >&2; exit 2 ;;
      esac
      shift
    done
    api="http://127.0.0.1:${toString cfg.httpPort}"
    ledger=${lib.escapeShellArg ledger}
    if [ "$command" = capture ] || [ "$command" = drift ]; then
      [ -s ${lib.escapeShellArg (if adminPassword == null then "/dev/null" else adminPassword)} ] || { echo "Gotify administrator password file is unavailable" >&2; exit 2; }
      token="${lib.escapeShellArg cfg.admin.username}:$(cat ${lib.escapeShellArg (if adminPassword == null then "/dev/null" else adminPassword)})"
      users=$(curl --fail --silent --show-error -u "$token" "$api/user")
      applications=$(curl --fail --silent --show-error -u "$token" "$api/application")
      if [ -n "$extra_user" ] && [ -s "$extra_password_file" ]; then
        extra_password=$(cat "$extra_password_file")
        extra_applications=$(curl --fail --silent --show-error -u "$extra_user:$extra_password" "$api/application")
        applications=$(jq -cn --argjson current "$applications" --argjson extra "$extra_applications" --arg admin_user ${lib.escapeShellArg cfg.admin.username} --arg extra_user "$extra_user" '$current | map(. + {owner:$admin_user}) + ($extra | map(. + {owner:$extra_user}))')
      else
        applications=$(jq -c --arg owner ${lib.escapeShellArg cfg.admin.username} 'map(. + {owner:$owner})' <<<"$applications")
      fi
      desired=$(if [ -e "$ledger" ]; then jq -cS . "$ledger"; else printf '%s' '{"users":[],"applications":[]}'; fi)
      report=$(jq -cn --argjson users "$users" --argjson applications "$applications" --argjson desired "$desired" --arg source "$command" --arg admin_user ${lib.escapeShellArg cfg.admin.username} '
        def observed_users: [$users[] | select(.admin != true) | {id,username:(.name // ""),admin:false,provenance:{source:"gotify-api",id:.id},password_file_required:true}];
        def observed_apps: [$applications[] | {id,name,description,owner:(.owner // $admin_user),provenance:{source:"gotify-api",id:.id},token_output_required:true}];
        (observed_users) as $ou | (observed_apps) as $oa |
        if $source == "capture" then
          {schema_version:1,complete:false,source:$source,users:$ou,applications:$oa,secrets:{redacted:true},findings:["password_file_required","token_output_required"]}
        else
          ([($desired.users[]? as $d | ($ou | map(select(.username == $d.username)) | first) as $o |
             if $o == null then {kind:"missing",resource:"user",username:$d.username,declared:$d}
             else {kind:(if $o.admin == false then "matching" else "administrator-conflict" end),resource:"user",username:$o.username,observed:$o}
             end)] +
           [($desired.applications[]? as $d | ($oa | map(select(.id == $d.id)) | first) as $o |
             if $o == null then {kind:"missing",resource:"application",name:$d.name,declared:$d}
             elif ($o.name == $d.name and $o.description == $d.description) then {kind:"matching",resource:"application",name:$o.name,observed:$o}
             else {kind:"changed",resource:"application",name:$o.name,observed:$o,differences:[{field:"name",observed:$o.name,declared:$d.name},{field:"description",observed:$o.description,declared:$d.description}]}
             end)] ) as $classifications |
          {schema_version:1,complete:false,source:$source,users:$ou,applications:$oa,classifications:$classifications,secrets:{redacted:true},findings:["password_file_required","token_output_required"]}
        end')
    else
      [ -n "$input" ] && [ -r "$input" ] || { echo "--input is required for convert" >&2; exit 2; }
      report=$(jq -cS '
        {
          schema_version: 1,
          complete: false,
          source: "conversion",
          secrets: {redacted: true},
          findings: (.findings + ["operator_review_required"]),
          declaration: {
            services: {
              osmium: {
                gotify: {
                  users: (reduce .users[]? as $u ({};
                    .[$u.username] = {
                      username: $u.username,
                      passwordFile: ("/run/secrets/gotify-" + $u.username)
                    }
                  )),
                  applications: (reduce .applications[]? as $a ({};
                    .["app-" + ($a.id|tostring)] = {
                      owner: ($a.owner // "REVIEW_OWNER"),
                      name: $a.name,
                      description: ($a.description // ""),
                      output: {
                        secretPath: ("/run/secrets/gotify-app-" + ($a.id|tostring) + ".token"),
                        owner: "root",
                        group: "root",
                        mode: "0400",
                        persistent: false
                      }
                    }
                  ))
                }
              }
            }
          }
        }' "$input")
    fi
    if [ -n "$output" ]; then install -d -m 0750 "$(dirname "$output")"; printf '%s\n' "$report" > "$output"; else printf '%s\n' "$report"; fi
  '';
in
{
  options.services.osmium.gotify = {
    enable = lib.mkEnableOption "the Osmium Gotify service";
    package = lib.mkOption { type = lib.types.package; default = pkgs.gotify-server; description = "Gotify server package."; };
    stateDir = lib.mkOption { type = lib.types.str; default = "/var/lib/gotify"; description = "Persistent Gotify state directory."; };
    httpPort = lib.mkOption { type = lib.types.port; default = 8080; description = "Guest Gotify HTTP port."; };
    hostHttpPort = lib.mkOption { type = lib.types.port; default = 8080; description = "MicroVM host-forwarded Gotify HTTP port."; };
    environment = lib.mkOption { type = lib.types.attrs; default = { }; description = "Additional Gotify environment settings."; };
    admin = {
      enable = lib.mkEnableOption "Gotify administrator bootstrap";
      username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "admin"; description = "Gotify administrator username."; };
      passwordFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Runtime file containing the Gotify administrator password."; };
    };
    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: { options = {
        username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; description = "Gotify username."; };
        passwordFile = lib.mkOption { type = lib.types.path; description = "Runtime user password file."; };
      }; }));
      default = { };
      description = "Declarative non-administrator Gotify users.";
    };
    applications = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: { options = {
        owner = lib.mkOption { type = lib.types.str; description = "Declaration key of the owning Gotify user."; };
        name = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._ -]+"; description = "Gotify application name."; };
        description = lib.mkOption { type = lib.types.str; default = ""; description = "Gotify application description."; };
        output = {
          secretPath = lib.mkOption { type = lib.types.str; description = "Protected app-token output path."; };
          owner = lib.mkOption { type = lib.types.str; default = "root"; description = "Token output owner."; };
          group = lib.mkOption { type = lib.types.str; default = "root"; description = "Token output group."; };
          mode = lib.mkOption { type = lib.types.strMatching "0[0-7]{3}"; default = "0400"; description = "Token output mode."; };
          persistent = lib.mkOption { type = lib.types.bool; default = true; description = "Persist the token output."; };
        };
      }; }));
      default = { };
      description = "Declarative Gotify applications and generated tokens.";
    };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = lib.hasPrefix "/var/lib/" cfg.stateDir; message = "services.osmium.gotify.stateDir must be below /var/lib."; }
      { assertion = !cfg.admin.enable || cfg.admin.passwordFile != null; message = "Gotify administrator passwordFile is required when bootstrap is enabled."; }
      { assertion = !enabledUsers || cfg.admin.enable; message = "Gotify users and applications require administrator bootstrap."; }
      { assertion = lib.length (lib.unique (map (user: user.username) users)) == lib.length users; message = "Gotify usernames must be unique."; }
      { assertion = lib.all (user: user.username != cfg.admin.username) users; message = "Gotify declared users must not use the administrator username."; }
      { assertion = lib.all (app: builtins.hasAttr app.owner cfg.users) applications; message = "Gotify applications must reference declared users."; }
      { assertion = lib.length (lib.unique (map (app: "${app.owner}:${app.name}") applications)) == lib.length applications; message = "Gotify application identities must be unique per owner."; }
      { assertion = lib.all (app: lib.hasPrefix "/var/lib/" app.output.secretPath || lib.hasPrefix "/run/" app.output.secretPath) applications; message = "Gotify token outputs must be below /var/lib or /run."; }
      { assertion = lib.length (lib.unique [ cfg.hostHttpPort ]) == 1; message = "Gotify host HTTP port is invalid."; }
    ];

    users.users.gotify = { isSystemUser = true; group = "gotify"; home = stateDir; createHome = true; };
    users.groups.gotify = { };
    services.gotify = {
      enable = true;
      package = cfg.package;
      stateDirectoryName = lib.removePrefix "/var/lib/" stateDir;
      environment = cfg.environment // { GOTIFY_SERVER_PORT = cfg.httpPort; GOTIFY_SERVER_BIND_ADDRESS = "0.0.0.0"; };
    };
    systemd.services.gotify-server.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "gotify";
      Group = lib.mkForce "gotify";
      StateDirectory = lib.mkForce "";
      ExecStartPre = [ "+${pkgs.writeShellScript "osmium-gotify-fix-state-owner" "${pkgs.coreutils}/bin/chown -R gotify:gotify ${lib.escapeShellArg stateDir}"}" ];
      ExecStart = lib.mkIf cfg.admin.enable (lib.mkForce wrapper);
    };
    environment.persistence."/persistent".directories = [ { directory = stateDir; user = "gotify"; group = "gotify"; mode = "0750"; } ];
    environment.systemPackages = [ reverseTool ];

    systemd.services.osmium-gotify-admin-bootstrap = lib.mkIf cfg.admin.enable {
      description = "Bootstrap the Osmium Gotify administrator";
      wantedBy = [ "multi-user.target" ];
      after = [ "gotify-server.service" ];
      requires = [ "gotify-server.service" ];
      path = [ pkgs.curl pkgs.jq pkgs.coreutils ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "gotify"; Group = "gotify"; UMask = "0077"; ExecStart = pkgs.writeShellScript "osmium-gotify-admin-bootstrap" ''
        set -eu
        if [ -e ${lib.escapeShellArg bootstrapMarker} ]; then exit 0; fi
        password=$(cat ${lib.escapeShellArg cfg.admin.passwordFile})
        [ -n "$password" ] || { echo "Gotify administrator password file is empty" >&2; exit 1; }
        curl --fail --silent --show-error --retry 30 --retry-connrefused --retry-delay 1 -u "${lib.escapeShellArg cfg.admin.username}:$password" http://127.0.0.1:${toString cfg.httpPort}/current/user >/dev/null
        install -m 0640 /dev/null ${lib.escapeShellArg bootstrapMarker}
      ''; };
    };
    systemd.services.osmium-gotify-reconcile = lib.mkIf enabledUsers {
      description = "Reconcile declarative Osmium Gotify users and applications";
      wantedBy = [ "multi-user.target" ];
      after = [ "gotify-server.service" "osmium-gotify-admin-bootstrap.service" ];
      requires = [ "gotify-server.service" ] ++ lib.optional cfg.admin.enable "osmium-gotify-admin-bootstrap.service";
      path = [ pkgs.curl pkgs.jq pkgs.coreutils ];
      serviceConfig = { Type = "oneshot"; User = "root"; Group = "root"; UMask = "0077"; ExecStart = reconcile; };
    };
    system.activationScripts.osmium-gotify-reconcile = lib.mkIf enabledUsers { text = "${pkgs.systemd}/bin/systemctl restart osmium-gotify-reconcile.service || true"; };
  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = [ { from = "host"; proto = "tcp"; host.port = cfg.hostHttpPort; guest.port = cfg.httpPort; } ];
  });
}
