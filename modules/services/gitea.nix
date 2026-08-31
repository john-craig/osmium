{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.mythoclast.gitea;
  serverSettings = cfg.settings.server or { };
  databaseSettings = cfg.settings.database or { };
  adminBootstrapMarker = "${cfg.stateDir}/.mythoclast-admin-bootstrap-complete";
  adminRotationState = "${cfg.stateDir}/.mythoclast-admin-rotation";
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
