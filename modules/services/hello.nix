{ config, lib, pkgs, ... }:

let
  cfg = config.services.mythoclast.hello;
in
{
  options.services.mythoclast.hello = {
    enable = lib.mkEnableOption "the Mythoclast persistence test service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port on which the service listens.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mythoclast-hello";
      readOnly = true;
      description = "Directory containing service state.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.stateDirectory;
        message = "services.mythoclast.hello.stateDirectory must be below /var/lib.";
      }
    ];

    users.users.mythoclast-hello = {
      isSystemUser = true;
      group = "mythoclast-hello";
      uid = 991;
    };
    users.groups.mythoclast-hello = {
      gid = 991;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    environment.persistence."/persistent" = {
      directories = [
        {
          directory = cfg.stateDirectory;
          user = "mythoclast-hello";
          group = "mythoclast-hello";
          mode = "0750";
        }
      ];
    };

    systemd.services.mythoclast-hello = {
      description = "Mythoclast persistence test service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "mythoclast-hello";
        Group = "mythoclast-hello";
        StateDirectory = "mythoclast-hello";
        ExecStart = "${pkgs.python3}/bin/python -m http.server ${toString cfg.port} --directory ${cfg.stateDirectory}";
        Restart = "on-failure";
      };
    };
  };
}
