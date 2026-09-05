{ config, lib, pkgs, ... }:

let
  cfg = config.services.osmium.hello;
in
{
  options.services.osmium.hello = {
    enable = lib.mkEnableOption "the Osmium persistence test service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port on which the service listens.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/osmium-hello";
      readOnly = true;
      description = "Directory containing service state.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.stateDirectory;
        message = "services.osmium.hello.stateDirectory must be below /var/lib.";
      }
    ];

    users.users.osmium-hello = {
      isSystemUser = true;
      group = "osmium-hello";
      uid = 991;
    };
    users.groups.osmium-hello = {
      gid = 991;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    environment.persistence."/persistent" = {
      directories = [
        {
          directory = cfg.stateDirectory;
          user = "osmium-hello";
          group = "osmium-hello";
          mode = "0750";
        }
      ];
    };

    systemd.services.osmium-hello = {
      description = "Osmium persistence test service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "osmium-hello";
        Group = "osmium-hello";
        StateDirectory = "osmium-hello";
        ExecStart = "${pkgs.python3}/bin/python -m http.server ${toString cfg.port} --directory ${cfg.stateDirectory}";
        Restart = "on-failure";
      };
    };
  };
}
