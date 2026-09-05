{ config, lib, ... }:

{
  imports = [
    (lib.mkAliasOptionModule [ "mythoclast" "host" ] [ "osmium" "host" ])
  ];

  options.osmium.host = {
    enable = lib.mkEnableOption "the Osmium MicroVM host integration";

    autostart = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "MicroVM names to start with the host.";
    };
  };

  config = lib.mkIf config.osmium.host.enable {
    microvm.autostart = config.osmium.host.autostart;
  };
}
