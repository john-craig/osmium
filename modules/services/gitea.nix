{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.mythoclast.gitea;
  serverSettings = cfg.settings.server or { };
  databaseSettings = cfg.settings.database or { };
  adminBootstrapMarker = "${cfg.stateDir}/.mythoclast-admin-bootstrap-complete";
  adminRotationState = "${cfg.stateDir}/.mythoclast-admin-rotation";
  identityDefinitions = lib.attrValues cfg.users;
  identityReconciliationEnabled = cfg.users != { } || cfg.organizations != { };
  adminCredentialFile = cfg.admin.passwordFile;
  adminRotationPasswordFile = if cfg.admin.rotation.passwordFile == null then "/dev/null" else cfg.admin.rotation.passwordFile;
  userReconciliation = lib.concatMapStringsSep "\n" (name:
    let
      user = cfg.users.${name};
      state = "${cfg.stateDir}/.mythoclast-user-${name}";
    in
    ''
      user_password=$(cat ${lib.escapeShellArg user.passwordFile})
      if [ -z "$user_password" ]; then
        echo "Gitea user password file for ${lib.escapeShellArg user.username} is empty" >&2
        exit 1
      fi
      user_status=$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' --user "$admin_username:$admin_password" \
        "http://127.0.0.1:${toString cfg.httpPort}/api/v1/users/${lib.escapeShellArg user.username}")
      case "$user_status" in
        200) ;;
        404)
          ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user create \
            --username ${lib.escapeShellArg user.username} --password "$user_password" \
            --email ${lib.escapeShellArg user.email} --must-change-password=false
          ;;
        *)
          echo "Unable to inspect declared Gitea user ${lib.escapeShellArg user.username} (HTTP $user_status)" >&2
          exit 1
          ;;
      esac
      user_payload="$(${pkgs.jq}/bin/jq -cn \
        --arg login_name ${lib.escapeShellArg user.username} \
        --arg email ${lib.escapeShellArg user.email} \
        '{login_name: $login_name, email: $email, admin: false, must_change_password: false}')"
      ${pkgs.curl}/bin/curl --fail --silent --show-error --user "$admin_username:$admin_password" \
        -X PATCH "http://127.0.0.1:${toString cfg.httpPort}/api/v1/admin/users/${lib.escapeShellArg user.username}" \
        -H 'Content-Type: application/json' --data "$user_payload" >/dev/null
      user_salt=
      user_hash=
      if [ -f ${lib.escapeShellArg state} ]; then
        while IFS='=' read -r key value; do
          case "$key" in
            salt) user_salt=$value ;;
            applied_hash) user_hash=$value ;;
          esac
        done < ${lib.escapeShellArg state}
      fi
      if [ -z "$user_salt" ]; then
        user_salt=$(head -c 32 /dev/urandom | base64 -w 0)
      fi
      candidate_hash=$(printf '%s%s' "$user_salt" "$user_password" | sha256sum | cut -d ' ' -f 1)
      if [ "$candidate_hash" != "$user_hash" ]; then
        ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user change-password \
          --username ${lib.escapeShellArg user.username} --password "$user_password" \
          --must-change-password=false
        user_tmp=$(mktemp ${lib.escapeShellArg "${state}.XXXXXX"})
        trap 'rm -f "$user_tmp"' EXIT
        printf 'salt=%s\napplied_hash=%s\n' "$user_salt" "$candidate_hash" > "$user_tmp"
        chmod 0640 "$user_tmp"
        mv "$user_tmp" ${lib.escapeShellArg state}
        trap - EXIT
      fi
    '') (lib.attrNames cfg.users);
  organizationReconciliation = lib.concatMapStringsSep "\n" (name:
    let
      organization = cfg.organizations.${name};
      owner = lib.findFirst (user: user.username == organization.owner) null identityDefinitions;
      ownerPasswordFile = if owner == null then "/dev/null" else owner.passwordFile;
    in
    ''
      owner_password=$(cat ${lib.escapeShellArg ownerPasswordFile})
      if [ -z "$owner_password" ]; then
        echo "Gitea owner password file for ${lib.escapeShellArg organization.owner} is empty" >&2
        exit 1
      fi
      organization_status=$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' \
        --user ${lib.escapeShellArg organization.owner}:"$owner_password" \
        "http://127.0.0.1:${toString cfg.httpPort}/api/v1/orgs/${lib.escapeShellArg organization.name}")
      organization_payload="$(${pkgs.jq}/bin/jq -cn \
        --arg username ${lib.escapeShellArg organization.name} \
        --arg description ${lib.escapeShellArg organization.description} \
        --arg visibility ${lib.escapeShellArg organization.visibility} \
        '{username: $username, description: $description, visibility: $visibility}')"
      case "$organization_status" in
        200)
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --user ${lib.escapeShellArg organization.owner}:"$owner_password" \
            -X PATCH "http://127.0.0.1:${toString cfg.httpPort}/api/v1/orgs/${lib.escapeShellArg organization.name}" \
            -H 'Content-Type: application/json' --data "$organization_payload" >/dev/null
          ;;
        404)
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --user ${lib.escapeShellArg organization.owner}:"$owner_password" \
            -X POST "http://127.0.0.1:${toString cfg.httpPort}/api/v1/orgs" \
            -H 'Content-Type: application/json' --data "$organization_payload" >/dev/null
          ;;
        *)
          echo "Unable to inspect declared Gitea organization ${lib.escapeShellArg organization.name} (HTTP $organization_status)" >&2
          exit 1
          ;;
      esac
    '') (lib.attrNames cfg.organizations);
in
{
  options.services.mythoclast.gitea = {
    enable = lib.mkEnableOption "the Mythoclast Gitea service";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gitea";
      description = "Directory containing all Gitea application state.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Guest TCP port for the Gitea HTTP server.";
    };

    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Guest TCP port for the Gitea SSH server.";
    };

    hostHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Host TCP port forwarded to the Gitea HTTP server.";
    };

    hostSshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Host TCP port forwarded to the Gitea SSH server.";
    };

    databasePasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional file containing the Gitea database password.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional declarative settings for Gitea.";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          username = lib.mkOption {
            type = lib.types.str;
            description = "Stable Gitea username for this non-admin identity.";
          };
          email = lib.mkOption {
            type = lib.types.str;
            description = "Email address for this non-admin Gitea user.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.path;
            description = "Runtime file containing this user's password.";
          };
        };
      }));
      default = { };
      description = "Declarative non-administrator Gitea users.";
    };

    organizations = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Stable Gitea organization name.";
          };
          owner = lib.mkOption {
            type = lib.types.str;
            description = "Username of the declared organization owner.";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Description for the Gitea organization.";
          };
          visibility = lib.mkOption {
            type = lib.types.enum [ "public" "limited" "private" ];
            default = "private";
            description = "Visibility of the Gitea organization.";
          };
        };
      }));
      default = { };
      description = "Declarative Gitea organizations owned by declared users.";
    };

    admin = {
      enable = lib.mkEnableOption "the initial Gitea administrator bootstrap";

      username = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Username for the initial Gitea administrator.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "admin@localhost";
        description = "Email address for the initial Gitea administrator.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Runtime file containing the initial administrator password.";
      };

      rotation = {
        enable = lib.mkEnableOption "automatic Gitea administrator credential rotation";

        passwordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Runtime file containing the desired replacement administrator password.";
        };

        maxAge = lib.mkOption {
          type = lib.types.ints.positive;
          default = 90 * 24 * 60 * 60;
          description = "Maximum administrator credential age in seconds.";
        };

        checkInterval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 60 * 60;
          description = "Interval between administrator credential rotation checks in seconds.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.stateDir;
        message = "services.mythoclast.gitea.stateDir must be below /var/lib.";
      }
      {
        assertion = cfg.hostHttpPort != cfg.hostSshPort;
        message = "Gitea HTTP and SSH host ports must be different.";
      }
      {
        assertion = !cfg.admin.enable || cfg.admin.passwordFile != null;
        message = "services.mythoclast.gitea.admin.passwordFile is required when administrator bootstrap is enabled.";
      }
      {
        assertion = !cfg.admin.rotation.enable || cfg.admin.enable;
        message = "Gitea administrator credential rotation requires administrator bootstrap to be enabled.";
      }
      {
        assertion = !cfg.admin.rotation.enable || cfg.admin.rotation.passwordFile != null;
        message = "services.mythoclast.gitea.admin.rotation.passwordFile is required when credential rotation is enabled.";
      }
      {
        assertion = !identityReconciliationEnabled || cfg.admin.enable;
        message = "Declarative Gitea users and organizations require administrator bootstrap to be enabled.";
      }
      {
        assertion = !identityReconciliationEnabled || adminCredentialFile != null;
        message = "Declarative Gitea users and organizations require an administrator credential file.";
      }
      {
        assertion = lib.length (lib.unique (map (user: user.username) identityDefinitions)) == lib.length identityDefinitions;
        message = "Declarative Gitea user usernames must be unique.";
      }
      {
        assertion = lib.all (user: user.username != cfg.admin.username) identityDefinitions;
        message = "Declarative Gitea users must not use the administrator username.";
      }
      {
        assertion = lib.all (user: builtins.match "[A-Za-z0-9._-]+" user.username != null) identityDefinitions;
        message = "Declarative Gitea usernames may contain only letters, numbers, dots, underscores, and hyphens.";
      }
      {
        assertion = lib.all (organization:
          builtins.match "[A-Za-z0-9._-]+" organization.name != null
          && lib.any (user: user.username == organization.owner) identityDefinitions
        ) (lib.attrValues cfg.organizations);
        message = "Declarative Gitea organizations require safe names and declared user owners.";
      }
    ];

    users.users.gitea = {
      uid = 992;
      isSystemUser = true;
      group = "gitea";
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.gitea.gid = 992;

    services.gitea = {
      enable = true;
      user = "gitea";
      group = "gitea";
      stateDir = cfg.stateDir;
      database = {
        type = "sqlite3";
        path = "${cfg.stateDir}/data/gitea.db";
      } // lib.optionalAttrs (cfg.databasePasswordFile != null) {
        passwordFile = cfg.databasePasswordFile;
      };
      settings = cfg.settings // {
        server = serverSettings // {
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = cfg.httpPort;
          SSH_PORT = cfg.sshPort;
        };
        database = databaseSettings // {
          DB_TYPE = "sqlite3";
          PATH = "${cfg.stateDir}/data/gitea.db";
        };
      };
    };

    environment.persistence."/persistent".directories = [
      {
        directory = cfg.stateDir;
        user = "gitea";
        group = "gitea";
        mode = "0750";
      }
    ];

    systemd.services.mythoclast-gitea-admin-bootstrap = lib.mkIf cfg.admin.enable {
      description = "Bootstrap the Mythoclast Gitea administrator";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" ];
      requires = [ "gitea.service" ];
      unitConfig.ConditionPathExists = "!${adminBootstrapMarker}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "mythoclast-gitea-admin-bootstrap" ''
          set -eu
          password=$(cat ${lib.escapeShellArg cfg.admin.passwordFile})
          ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user create \
            --username ${lib.escapeShellArg cfg.admin.username} \
            --password "$password" \
            --email ${lib.escapeShellArg cfg.admin.email} \
            --admin \
            --must-change-password=false
          install -m 0640 /dev/null ${lib.escapeShellArg adminBootstrapMarker}
        '';
      };
    };

    systemd.services.mythoclast-gitea-admin-rotation = lib.mkIf cfg.admin.rotation.enable {
      description = "Rotate the Mythoclast Gitea administrator credential";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" ];
      requires = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "mythoclast-gitea-admin-rotation" ''
          set -eu
          state=${lib.escapeShellArg adminRotationState}
          password_file=${lib.escapeShellArg cfg.admin.rotation.passwordFile}
          now=$(date +%s)
          password=$(cat "$password_file")
          if [ -z "$password" ]; then
            echo "Gitea administrator rotation password file is empty" >&2
            exit 1
          fi

          salt=
          applied_at=0
          applied_hash=
          if [ -f "$state" ]; then
            while IFS='=' read -r key value; do
              case "$key" in
                salt) salt=$value ;;
                applied_at) applied_at=$value ;;
                applied_hash) applied_hash=$value ;;
              esac
            done < "$state"
          fi

          if [ -z "$salt" ]; then
            salt=$(head -c 32 /dev/urandom | base64 -w 0)
          fi
          candidate_hash=$(printf '%s%s' "$salt" "$password" | sha256sum | cut -d ' ' -f 1)

          if [ "$candidate_hash" = "$applied_hash" ]; then
            if [ "$((now - applied_at))" -lt ${toString cfg.admin.rotation.maxAge} ]; then
              exit 0
            fi
            echo "Gitea administrator rotation is due, but the replacement credential is unchanged" >&2
            exit 1
          fi

          ${pkgs.gitea}/bin/gitea --config ${lib.escapeShellArg "${cfg.stateDir}/custom/conf/app.ini"} admin user change-password \
            --username ${lib.escapeShellArg cfg.admin.username} \
            --password "$password" \
            --must-change-password=false

          tmp=$(mktemp "''${state}.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          printf 'salt=%s\napplied_at=%s\napplied_hash=%s\n' "$salt" "$now" "$candidate_hash" > "$tmp"
          chmod 0640 "$tmp"
          mv "$tmp" "$state"
        '';
      };
    };

    systemd.timers.mythoclast-gitea-admin-rotation = lib.mkIf cfg.admin.rotation.enable {
      description = "Check the Mythoclast Gitea administrator credential age";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "${toString cfg.admin.rotation.checkInterval}s";
        OnUnitActiveSec = "${toString cfg.admin.rotation.checkInterval}s";
        Unit = "mythoclast-gitea-admin-rotation.service";
      };
    };

    system.activationScripts.mythoclast-gitea-admin-rotation = lib.mkIf cfg.admin.rotation.enable {
      text = ''
        ${pkgs.systemd}/bin/systemctl restart mythoclast-gitea-admin-rotation.service || true
      '';
    };

    systemd.services.mythoclast-gitea-identities = lib.mkIf identityReconciliationEnabled {
      description = "Reconcile declarative Mythoclast Gitea users and organizations";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" "mythoclast-gitea-admin-rotation.service" ];
      requires = [ "gitea.service" "mythoclast-gitea-admin-bootstrap.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "mythoclast-gitea-identities" ''
          set -eu
          admin_username=${lib.escapeShellArg cfg.admin.username}
          admin_password=$(cat ${lib.escapeShellArg adminCredentialFile})
          if [ -n "$admin_password" ] && [ -f ${lib.escapeShellArg adminRotationState} ]; then
            if [ ! -s ${lib.escapeShellArg adminRotationPasswordFile} ]; then
              echo "Skipping Gitea identity reconciliation until the rotated administrator credential is available"
              exit 0
            fi
          fi
          if [ -s ${lib.escapeShellArg adminRotationPasswordFile} ]; then
            admin_password=$(cat ${lib.escapeShellArg adminRotationPasswordFile})
          fi
          if [ -z "$admin_password" ]; then
            echo "Gitea administrator credential file is empty" >&2
            exit 1
          fi
          ${userReconciliation}
          ${organizationReconciliation}
        '';
      };
    };

    system.activationScripts.mythoclast-gitea-identities = lib.mkIf identityReconciliationEnabled {
      text = ''
        ${pkgs.systemd}/bin/systemctl restart mythoclast-gitea-identities.service || true
      '';
    };

  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = [
      {
        from = "host";
        proto = "tcp";
        host.port = cfg.hostHttpPort;
        guest.port = cfg.httpPort;
      }
      {
        from = "host";
        proto = "tcp";
        host.port = cfg.hostSshPort;
        guest.port = cfg.sshPort;
      }
    ];
  });
}
