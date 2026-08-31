{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.mythoclast.gitea;
  serverSettings = cfg.settings.server or { };
  databaseSettings = cfg.settings.database or { };
  adminBootstrapMarker = "${cfg.stateDir}/.mythoclast-admin-bootstrap-complete";
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
