{ self, ... }:

{
  imports = [ self.nixosModules.host ];

  system.stateVersion = "25.05";

  osmium.host = {
    enable = true;
    autostart = [ "demo" ];
  };

  # A fully declarative VM can be supplied here with the same guest modules
  # used by nixosConfigurations.demo-guest.
}
