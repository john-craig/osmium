{ config, lib, ... }:

{
  options.mythoclast.host = {
    enable = lib.mkEnableOption "the Mythoclast MicroVM host integration";

    autostart = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "MicroVM names to start with the host.";
    };
  };

  config = lib.mkIf config.mythoclast.host.enable {
    microvm.autostart = config.mythoclast.host.autostart;
  };
}
