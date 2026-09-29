{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.authelia;
  stateDir = cfg.stateDir;
  runtimeDir = "/run/osmium-authelia";
  usersFile = "${stateDir}/users.yml";
  databaseFile = "${stateDir}/db.sqlite3";
  ledgerFile = "${stateDir}/.osmium-authelia.json";
  ldapRuntimeFile = "${runtimeDir}/ldap.json";
  declaredUsers = lib.attrValues cfg.users;
  declaredGroups = lib.attrValues cfg.groups;
  userSecretPaths = lib.concatMap (user:
    [ user.passwordFile ]
    ++ lib.optional (user.totp.bootstrapFile != null) user.totp.bootstrapFile
    ++ lib.optional (user.totp.outputFile != null) user.totp.outputFile
  ) declaredUsers;
  portalHost = builtins.elemAt (lib.splitString "/" (lib.removePrefix "https://" (lib.removePrefix "http://" cfg.portalUrl))) 0;
  accessRules = map
    (rule: {
      domain = rule.domain;
      policy = rule.policy;
      resources = rule.resources;
      subject = rule.subject;
    })
    cfg.accessControl.rules
    ++ lib.optional (cfg.accessControl.rules == [ ]) {
      domain = "*";
      policy = "deny";
      resources = [ ];
      subject = [ ];
    };
  fileBackend = {
    path = usersFile;
    watch = true;
  };
  ldapBackend = {
    implementation = "lldap";
    address = cfg.ldap.address;
    base_dn = cfg.ldap.baseDn;
    additional_users_dn = "ou=people";
    additional_groups_dn = "ou=groups";
    user = cfg.ldap.bindDn;
    users_filter = cfg.ldap.usersFilter;
    groups_filter = cfg.ldap.groupsFilter;
    attributes = {
      username = cfg.ldap.usernameAttribute;
      display_name = cfg.ldap.displayAttribute;
      mail = cfg.ldap.mailAttribute;
      group_name = cfg.ldap.groupNameAttribute;
      member_of = cfg.ldap.membershipAttribute;
    };
  };
  baseSettings = {
    theme = "auto";
    default_2fa_method = cfg.totp.defaultMethod;
    server = {
      address = "tcp://${cfg.listenAddress}:${toString cfg.listenPort}/";
      endpoints.authz.forward-auth = { implementation = "ForwardAuth"; };
    };
    log = {
      level = "info";
      format = "text";
      keep_stdout = true;
    };
    authentication_backend = {
      file = fileBackend;
    };
    storage.local = {
      path = databaseFile;
    };
    session.cookies = [ {
      name = "authelia_session";
      domain = portalHost;
      authelia_url = cfg.portalUrl;
    } ];
    access_control = {
      default_policy = cfg.accessControl.defaultPolicy;
      rules = accessRules;
    };
    notifier.filesystem = {
      filename = "${stateDir}/notifications.txt";
    };
  };
  baseConfigFile = (pkgs.formats.yaml { }).generate "osmium-authelia-config.yml" baseSettings;
  runtimeEnvironment = pkgs.writeShellScript "osmium-authelia-runtime-environment" ''
    set -eu
    install -d -m 0750 -o authelia -g authelia ${lib.escapeShellArg runtimeDir}
    install -m 0400 -o authelia -g authelia ${lib.escapeShellArg cfg.storageEncryptionKeyFile} ${lib.escapeShellArg "${runtimeDir}/storage-encryption-key"}
    ${lib.optionalString cfg.ldap.enable ''
      [ -s ${lib.escapeShellArg cfg.ldap.bindPasswordFile} ] || {
        echo "Authelia LDAP bind password file is unavailable or empty" >&2
        exit 1
      }
      ${if cfg.ldap.tls.enable then ''
        ${pkgs.jq}/bin/jq -n \
          --arg password "$(cat ${lib.escapeShellArg cfg.ldap.bindPasswordFile})" \
          --arg certificate "$(cat ${lib.escapeShellArg cfg.ldap.tls.certificateFile})" \
          '{authentication_backend:{ldap:{password:$password,tls:{certificate_chain:$certificate}}}}' > ${lib.escapeShellArg ldapRuntimeFile}
      '' else ''
        ${pkgs.jq}/bin/jq -n \
          --arg password "$(cat ${lib.escapeShellArg cfg.ldap.bindPasswordFile})" \
          '{authentication_backend:{ldap:{password:$password}}}' > ${lib.escapeShellArg ldapRuntimeFile}
      ''}
      chmod 0400 ${lib.escapeShellArg ldapRuntimeFile}
      chown authelia:authelia ${lib.escapeShellArg ldapRuntimeFile}
    ''}
  '';
  reconcile = pkgs.writeShellScript "osmium-authelia-reconcile" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.jq pkgs.gnused pkgs.gawk pkgs.openssl cfg.package ]}
    state=${lib.escapeShellArg stateDir}
    users_file=${lib.escapeShellArg usersFile}
    ledger=${lib.escapeShellArg ledgerFile}
    config_file=${lib.escapeShellArg baseConfigFile}
    runtime=${lib.escapeShellArg runtimeDir}
    install -d -m 0700 "$state" "$runtime"
    [ -r ${lib.escapeShellArg cfg.storageEncryptionKeyFile} ] || { echo "Authelia storage encryption key file is unavailable" >&2; exit 1; }
    [ -r ${lib.escapeShellArg cfg.jwtSecretFile} ] || { echo "Authelia JWT secret file is unavailable" >&2; exit 1; }
    [ -r ${lib.escapeShellArg cfg.sessionSecretFile} ] || { echo "Authelia session secret file is unavailable" >&2; exit 1; }
    [ -s ${lib.escapeShellArg cfg.storageEncryptionKeyFile} ] || { echo "Authelia storage encryption key file is empty" >&2; exit 1; }
    [ -s ${lib.escapeShellArg cfg.jwtSecretFile} ] || { echo "Authelia JWT secret file is empty" >&2; exit 1; }
    [ -s ${lib.escapeShellArg cfg.sessionSecretFile} ] || { echo "Authelia session secret file is empty" >&2; exit 1; }
    if [ ! -e "$ledger" ]; then
      printf '%s\n' '{"schema_version":1,"users":{},"totp":{}}' > "$ledger"
      chmod 0600 "$ledger"
    fi
    ${lib.optionalString (cfg.users != { }) ''
      tmp_users=$(mktemp "$users_file.XXXXXX")
      trap 'rm -f "$tmp_users"' EXIT
      users_json='{}'
      ${lib.concatMapStringsSep "\n" (name:
        let user = cfg.users.${name};
        in ''
          password=$(cat ${lib.escapeShellArg user.passwordFile})
          [ -n "$password" ] || { echo "Authelia password file is empty: ${lib.escapeShellArg name}" >&2; exit 1; }
          salt=$(${pkgs.jq}/bin/jq -r --arg name ${lib.escapeShellArg name} '.users[$name].salt // empty' "$ledger")
          [ -n "$salt" ] || salt=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
          fingerprint=$(printf '%s%s' "$salt" "$password" | sha256sum | cut -d' ' -f1)
          old_fingerprint=$(${pkgs.jq}/bin/jq -r --arg name ${lib.escapeShellArg name} '.users[$name].fingerprint // empty' "$ledger")
           old_hash=$(${pkgs.jq}/bin/jq -r --arg name ${lib.escapeShellArg name} '.users[$name].password // empty' "$users_file" 2>/dev/null || true)
          if [ -z "$old_hash" ] || [ "$old_fingerprint" != "$fingerprint" ]; then
            hash=$(authelia crypto hash generate argon2 --password "$password" --no-confirm | sed -n 's/^Digest:[[:space:]]*//p' | tail -n 1)
            [ -n "$hash" ] || { echo "Authelia password hashing failed for ${lib.escapeShellArg name}" >&2; exit 1; }
          else
            hash="$old_hash"
          fi
          users_json=$(${pkgs.jq}/bin/jq -c --arg name ${lib.escapeShellArg name} --arg hash "$hash" --arg display ${lib.escapeShellArg user.displayName} --arg email ${lib.escapeShellArg user.email} --argjson disabled ${lib.boolToString (!user.enabled)} --argjson groups ${lib.escapeShellArg (builtins.toJSON user.groups)} '. + {($name):{disabled:$disabled,displayname:$display,email:$email,password:$hash,groups:$groups}}' <<<"$users_json")
           ${pkgs.jq}/bin/jq --arg name ${lib.escapeShellArg name} --arg salt "$salt" --arg fingerprint "$fingerprint" '.users[$name]={salt:$salt,fingerprint:$fingerprint,status:"applied"}' "$ledger" > "$ledger.next"
          chmod 0600 "$ledger.next"
          mv -f "$ledger.next" "$ledger"
        '') (lib.attrNames cfg.users)}
      ${pkgs.jq}/bin/jq -n --argjson users "$users_json" '{users:$users}' > "$tmp_users"
      ${pkgs.jq}/bin/jq empty "$tmp_users"
      mv -f "$tmp_users" "$users_file"
      chmod 0600 "$users_file"
      chown authelia:authelia "$users_file"
    ''}
    ${lib.optionalString (cfg.users == { }) ''
      if [ ! -e "$users_file" ]; then
        printf '%s\n' '{"users":{}}' > "$users_file"
        chmod 0600 "$users_file"
        chown authelia:authelia "$users_file"
      fi
    ''}
    ${lib.optionalString cfg.ldap.enable ''
      [ -s ${lib.escapeShellArg cfg.ldap.bindPasswordFile} ] || exit 1
    ''}
    chown authelia:authelia "$ledger"
  '';
  totpBootstrap = pkgs.writeShellScript "osmium-authelia-totp-bootstrap" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq cfg.package ]}
    ledger=${lib.escapeShellArg ledgerFile}
    until curl --fail --silent http://127.0.0.1:${toString cfg.listenPort}/api/health >/dev/null; do sleep 1; done
    ${lib.concatMapStringsSep "\n" (name:
      let user = cfg.users.${name};
      in lib.optionalString (user.totp.bootstrapFile != null) ''
        if [ ! -s ${lib.escapeShellArg user.totp.bootstrapFile} ]; then exit 1; fi
        done=$(${pkgs.jq}/bin/jq -r --arg name ${lib.escapeShellArg name} '.totp[$name] // false' "$ledger")
        done=$(${pkgs.jq}/bin/jq -r --arg name ${lib.escapeShellArg name} '.totp[$name] // false' "$ledger")
        if [ "$done" != true ]; then
          secret=$(cat ${lib.escapeShellArg user.totp.bootstrapFile})
          [ -n "$secret" ] || exit 1
          authelia storage user totp generate ${lib.escapeShellArg user.username} --config ${lib.escapeShellArg baseConfigFile} --sqlite.path ${lib.escapeShellArg databaseFile} --encryption-key "$(cat ${lib.escapeShellArg "${runtimeDir}/storage-encryption-key"})" --secret "$secret" ${lib.optionalString (user.totp.outputFile != null) "--path ${lib.escapeShellArg user.totp.outputFile}"}
          ${pkgs.jq}/bin/jq --arg name ${lib.escapeShellArg name} '.totp[$name]=true' "$ledger" > "$ledger.next"
          chmod 0600 "$ledger.next"; mv -f "$ledger.next" "$ledger"
        fi
      '') (lib.attrNames cfg.users)}
  '';
  observe = pkgs.writeShellScriptBin "osmium-authelia-observe" ''
    set -eu
    output=""
    origin="runtime-observation"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --output) output=$2; shift 2 ;;
        --capture) origin="live-capture"; shift ;;
        *) echo "usage: osmium-authelia-observe [--capture] [--output FILE]" >&2; exit 2 ;;
      esac
    done
    actual_users=$(${pkgs.jq}/bin/jq -c '.users // {}' ${lib.escapeShellArg usersFile} 2>/dev/null || printf '{}')
    report=$(${pkgs.jq}/bin/jq -nS \
      --arg origin "$origin" \
      --arg portal ${lib.escapeShellArg cfg.portalUrl} \
      --arg state ${lib.escapeShellArg stateDir} \
      --arg backend ${if cfg.ldap.enable then "ldap" else "file"} \
      --argjson actual_users "$actual_users" \
      --argjson declared_users ${lib.escapeShellArg (builtins.toJSON (lib.mapAttrsToList (name: user: { inherit name; username = user.username; passwordFile = user.passwordFile; }) cfg.users))} \
      --argjson groups ${lib.escapeShellArg (builtins.toJSON (lib.mapAttrsToList (name: group: { inherit name; displayName = group.displayName; users = group.users; }) cfg.groups))} \
      '{
        schema_version:1,
        source:{origin:$origin,scope:"guest-runtime",review_only:true},
        provenance:{observed_fields:["service","users.yml","groups","access_control"],secret_policy:"secret-bytes-excluded"},
        complete:false,
        activation_ready:false,
        service:{portalUrl:$portal,stateDir:$state,backend:$backend},
        users:($actual_users | to_entries | map(
          . as $entry |
          ($declared_users | map(select(.username == $entry.key)) | .[0]) as $declared |
          {name:($declared.name // $entry.key),username:$entry.key,displayName:($entry.value.displayname // ""),email:($entry.value.email // ""),groups:($entry.value.groups // []),enabled:(($entry.value.disabled // false) | not),managed:($declared != null),passwordFile:{unresolved:true,path:($declared.passwordFile // null)}}
        )),
        groups:$groups,
        accessControl:${builtins.toJSON cfg.accessControl},
        secrets:{excluded:true,unresolved:["jwtSecretFile","storageEncryptionKeyFile","sessionSecretFile","users.*.passwordFile","ldap.bindPasswordFile"]},
        findings:[{code:"secret-excluded",scope:"all"},{code:"operator-review-required",scope:"all"}]
      }' )
    if [ -n "$output" ]; then install -d -m 0750 "$(dirname "$output")"; printf '%s\n' "$report" > "$output"; else printf '%s\n' "$report"; fi
  '';
  candidate = pkgs.writeShellScriptBin "osmium-authelia-candidate" ''
    set -eu
    [ "''${1:-}" = "--input" ] && [ -r "''${2:-}" ] || { echo "usage: osmium-authelia-candidate --input OBSERVATION" >&2; exit 2; }
    ${pkgs.jq}/bin/jq -cS '{schema_version:1,complete:false,activation_ready:false,provenance:(.source + {conversion:"review-only",derived_from:"runtime-observation"}),declaration:{services:{osmium:{authelia:{portalUrl:.service.portalUrl,users:(.users | map({key:(.name),value:{username:.username,displayName:.displayName,email:.email,groups:.groups,enabled:.enabled,passwordFile:.passwordFile}}) | from_entries),groups:(.groups | map({key:.name,value:{displayName:.displayName,users:.users}}) | from_entries),accessControl:.accessControl}}}},secrets:{excluded:true},unresolved:.secrets.unresolved,findings:(.findings + [{code:"operator-review-required",scope:"all"},{code:"unresolved-secret-reference",scope:"secret-backed-fields"}])}' "$2"
  '';
  drift = pkgs.writeShellScriptBin "osmium-authelia-drift" ''
    set -eu
    observation=""; declared=""; output=""
    while [ "$#" -gt 0 ]; do case "$1" in --observation) observation=$2; shift 2;; --declared) declared=$2; shift 2;; --output) output=$2; shift 2;; *) echo "usage: osmium-authelia-drift --observation FILE --declared FILE [--output FILE]" >&2; exit 2;; esac; done
    [ -r "$observation" ] && [ -r "$declared" ] || { echo "observation and declared files are required" >&2; exit 2; }
     result=$(${pkgs.jq}/bin/jq -cS --slurpfile declared "$declared" '. as $o | $declared[0] as $d | {schema_version:1,complete:false,activation_ready:false,provenance:(.source + {conversion:"review-only-drift",derived_from:"runtime-observation"}),changes:([{resource:"service",kind:(if $o.service.backend == ($d.backend // "file") then "matching" else "changed" end),differences:[]}] + [$o.users[] | select(.managed != true) | {resource:"user",name:.username,kind:"unmanaged",differences:[]}]),candidate:$o,secrets:{excluded:true},findings:($o.findings + [{code:"non-mutating-review-only",scope:"all"},{code:"unresolved-secret-reference",scope:"secret-backed-fields"}])}' "$observation")
    if [ -n "$output" ]; then printf '%s\n' "$result" > "$output"; else printf '%s\n' "$result"; fi
  '';
in
{
  options.services.osmium.authelia = {
    enable = lib.mkEnableOption "the Osmium Authelia service";
    package = lib.mkPackageOption pkgs "authelia" { };
    portalUrl = lib.mkOption { type = lib.types.strMatching "https://[^[:space:]]+"; default = "https://auth.example.invalid"; description = "External HTTPS Authelia portal URL."; };
    listenAddress = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "Loopback Authelia listener address."; };
    listenPort = lib.mkOption { type = lib.types.port; default = 9091; description = "Guest Authelia listener port."; };
    hostPort = lib.mkOption { type = lib.types.nullOr lib.types.port; default = null; description = "Optional host diagnostic port forwarding."; };
    stateDir = lib.mkOption { type = lib.types.str; default = "/var/lib/authelia"; description = "Persistent Authelia state directory."; };
    jwtSecretFile = lib.mkOption { type = lib.types.str; description = "Runtime JWT secret file."; };
    storageEncryptionKeyFile = lib.mkOption { type = lib.types.str; description = "Runtime storage encryption key file."; };
    sessionSecretFile = lib.mkOption { type = lib.types.str; description = "Runtime session secret file."; };
    identityValidationSecretFile = lib.mkOption { type = lib.types.str; default = ""; description = "Optional runtime identity-validation secret file."; };
    users = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          username = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; description = "Stable Authelia username."; };
          enabled = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the user is enabled."; };
          displayName = lib.mkOption { type = lib.types.strMatching ".+"; description = "User display name."; };
          email = lib.mkOption { type = lib.types.strMatching "[^[:space:]@]+@[^[:space:]@]+"; description = "User email."; };
          groups = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Declared group keys."; };
          passwordFile = lib.mkOption { type = lib.types.str; description = "Runtime password file."; };
          totp = {
            bootstrapFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Protected marker/input enabling one-time TOTP bootstrap."; };
            outputFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Protected TOTP enrollment output path."; };
          };
        };
      }));
      description = "Declarative local Authelia users.";
    };
    groups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          displayName = lib.mkOption { type = lib.types.strMatching ".+"; description = "Group display name."; };
          users = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Declared user keys."; };
        };
      }));
      description = "Declarative Authelia groups.";
    };
    totp.defaultMethod = lib.mkOption { type = lib.types.enum [ "" "totp" ]; default = ""; description = "Default second-factor method."; };
    accessControl = {
      defaultPolicy = lib.mkOption { type = lib.types.enum [ "deny" "one_factor" "two_factor" "bypass" ]; default = "deny"; description = "Default access policy."; };
      rules = lib.mkOption {
        default = [ ];
        type = lib.types.listOf (lib.types.submodule ({ ... }: {
          options = {
            domain = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._*-]+"; description = "Exact or wildcard destination domain."; };
            policy = lib.mkOption { type = lib.types.enum [ "bypass" "one_factor" "two_factor" "deny" ]; description = "Rule policy."; };
            resources = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Optional request resources."; };
            subject = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Optional users or groups."; };
          };
        }));
        description = "Ordered access-control rules.";
      };
    };
    ldap = {
      enable = lib.mkEnableOption "LLDAP authentication";
      address = lib.mkOption { type = lib.types.strMatching "ldaps?://[^[:space:]]+"; default = "ldap://127.0.0.1:3890"; description = "LLDAP LDAP endpoint."; };
      baseDn = lib.mkOption { type = lib.types.strMatching "(dc=[A-Za-z0-9-]+)(,dc=[A-Za-z0-9-]+)*"; default = "dc=example,dc=com"; description = "LDAP base DN."; };
      bindDn = lib.mkOption { type = lib.types.strMatching ".+"; default = "uid=authelia-bind,ou=people,dc=example,dc=com"; description = "Dedicated LDAP bind DN."; };
      bindPasswordFile = lib.mkOption { type = lib.types.str; default = "/run/secrets/authelia-ldap-bind-password"; description = "Runtime LDAP bind password file."; };
      usersFilter = lib.mkOption { type = lib.types.str; default = "(&(|({username_attribute}={input})({mail_attribute}={input}))(objectClass=person))"; description = "Safe LDAP user filter."; };
      groupsFilter = lib.mkOption { type = lib.types.str; default = "(&(member={dn})(objectClass=groupOfNames))"; description = "Safe LDAP group filter."; };
      usernameAttribute = lib.mkOption { type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_-]*"; default = "uid"; description = "LDAP username attribute."; };
      displayAttribute = lib.mkOption { type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_-]*"; default = "displayName"; description = "LDAP display attribute."; };
      mailAttribute = lib.mkOption { type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_-]*"; default = "mail"; description = "LDAP email attribute."; };
      groupNameAttribute = lib.mkOption { type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_-]*"; default = "cn"; description = "LDAP group name attribute."; };
      membershipAttribute = lib.mkOption { type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_-]*"; default = "member"; description = "LDAP membership attribute."; };
      tls = {
        enable = lib.mkEnableOption "LDAP TLS";
        certificateFile = lib.mkOption { type = lib.types.str; default = ""; description = "Runtime LDAP CA trust file."; };
      };
    };
    reverseConfiguration.enable = lib.mkEnableOption "review-only Authelia reverse configuration tooling";
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = cfg.stateDir == "/var/lib/authelia"; message = "services.osmium.authelia.stateDir must be /var/lib/authelia because the native module owns StateDirectory."; }
      { assertion = lib.hasPrefix "https://" cfg.portalUrl; message = "services.osmium.authelia.portalUrl must use HTTPS."; }
      { assertion = cfg.listenAddress == "127.0.0.1" || cfg.listenAddress == "::1"; message = "services.osmium.authelia.listenAddress must be loopback-only."; }
       { assertion = lib.all (path: lib.hasPrefix "/" path && !lib.hasPrefix "/nix/store/" path) ([ cfg.jwtSecretFile cfg.storageEncryptionKeyFile cfg.sessionSecretFile cfg.ldap.bindPasswordFile ] ++ userSecretPaths); message = "Authelia runtime secret paths must be absolute and outside the Nix store."; }
      { assertion = lib.length (lib.unique (map (user: user.username) declaredUsers)) == lib.length declaredUsers; message = "Authelia usernames must be unique."; }
      { assertion = lib.length (lib.unique (map (user: user.email) declaredUsers)) == lib.length declaredUsers; message = "Authelia email addresses must be unique."; }
      { assertion = lib.all (user: lib.all (group: builtins.hasAttr group cfg.groups) user.groups) declaredUsers; message = "Authelia user groups must reference declared groups."; }
      { assertion = lib.all (group: lib.all (user: builtins.hasAttr user cfg.users) group.users) declaredGroups; message = "Authelia group users must reference declared users."; }
      { assertion = !cfg.ldap.enable || config.services.osmium.lldap.enable; message = "Authelia LDAP mode requires services.osmium.lldap.enable."; }
      { assertion = !cfg.ldap.enable || (cfg.ldap.address != "ldap://0.0.0.0:3890"); message = "Authelia LDAP must not use an unspecified insecure endpoint."; }
      { assertion = !cfg.ldap.tls.enable || cfg.ldap.tls.certificateFile != ""; message = "Authelia LDAP TLS requires a CA trust file."; }
    ];

    services.authelia.instances.main = {
      enable = true;
      name = "";
      package = cfg.package;
      secrets = {
        jwtSecretFile = cfg.jwtSecretFile;
        storageEncryptionKeyFile = cfg.storageEncryptionKeyFile;
        sessionSecretFile = cfg.sessionSecretFile;
      };
      settings = baseSettings // lib.optionalAttrs cfg.ldap.enable {
        authentication_backend = { ldap = ldapBackend; };
      };
      settingsFiles = lib.optional cfg.ldap.enable ldapRuntimeFile;
    };

    users.users.authelia = { isSystemUser = true; group = "authelia"; home = stateDir; };
    users.groups.authelia = { };
    systemd.services.osmium-authelia-runtime-environment = {
      description = "Prepare Authelia runtime-only integration settings";
      wantedBy = [ "multi-user.target" ];
      before = [ "authelia.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0077"; ExecStart = runtimeEnvironment; };
    };
    systemd.services.osmium-authelia-reconcile = {
      description = "Reconcile declarative Authelia identities";
      wantedBy = [ "multi-user.target" ];
      before = [ "authelia.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; Group = "root"; ExecStart = reconcile; UMask = "0077"; };
    };
    systemd.services.authelia = {
      after = [ "osmium-authelia-runtime-environment.service" "osmium-authelia-reconcile.service" ];
      requires = [ "osmium-authelia-runtime-environment.service" "osmium-authelia-reconcile.service" ];
      serviceConfig.ReadWritePaths = [ stateDir runtimeDir ];
    };
    systemd.services.osmium-authelia-totp-bootstrap = lib.mkIf (lib.any (user: user.totp.bootstrapFile != null) declaredUsers) {
      description = "Bootstrap declared Authelia TOTP factors once";
      wantedBy = [ "multi-user.target" ];
      after = [ "authelia.service" "osmium-authelia-reconcile.service" ];
      requires = [ "authelia.service" "osmium-authelia-reconcile.service" ];
      serviceConfig = { Type = "oneshot"; User = "authelia"; Group = "authelia"; ExecStart = totpBootstrap; UMask = "0077"; };
    };
    systemd.paths.osmium-authelia-reconcile = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = [ cfg.jwtSecretFile cfg.storageEncryptionKeyFile cfg.sessionSecretFile ]
          ++ map (user: user.passwordFile) declaredUsers
          ++ lib.optional cfg.ldap.enable cfg.ldap.bindPasswordFile;
        Unit = "osmium-authelia-reconcile.service";
      };
    };
    environment.persistence."/persistent".directories = [ { directory = stateDir; user = "authelia"; group = "authelia"; mode = "0700"; } ];
    environment.systemPackages = lib.optionals cfg.reverseConfiguration.enable [ observe candidate drift ];
  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = lib.optional (cfg.hostPort != null) { from = "host"; proto = "tcp"; host.port = cfg.hostPort; guest.port = cfg.listenPort; };
    networking.firewall.allowedTCPPorts = lib.optional (cfg.hostPort != null) cfg.listenPort;
  });
}
