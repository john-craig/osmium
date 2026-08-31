{
  description = "Reproducible, impermanent NixOS services in MicroVMs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";

    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, impermanence, microvm }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      guestModules = [
        microvm.nixosModules.microvm
        self.nixosModules.default
        {
          networking.hostName = "mythoclast-demo";
          system.stateVersion = "25.05";

          microvm = {
            hypervisor = "qemu";
            vcpu = 1;
            mem = 512;
            interfaces = [ {
              type = "user";
              id = "demo";
              mac = "02:00:00:00:00:01";
            } ];
          };

          services.mythoclast.hello = {
            enable = true;
            port = 8080;
          };
        }
      ];
    in
    {
      nixosModules.default = {
        imports = [
          impermanence.nixosModules.impermanence
          ./modules
        ];
      };

      nixosModules.host = {
        imports = [
          microvm.nixosModules.host
          ./modules/host.nix
        ];
      };

      nixosConfigurations.demo-guest = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = guestModules;
      };

      nixosConfigurations.demo-host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.host
          {
            system.stateVersion = "25.05";
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            boot.loader.grub.devices = [ "/dev/vda" ];
            mythoclast.host = {
              enable = true;
              autostart = [ "demo" ];
            };

            microvm.vms.demo = {
              config = {
                imports = guestModules;
              };
            };
          }
        ];
      };

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          module-evaluation = (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = guestModules;
          }).config.system.build.toplevel;

          persistence = import ./tests/persistence.nix {
            inherit pkgs;
            module = self.nixosModules.default;
          };
        });

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = with nixpkgs.legacyPackages.${system}; [
            nixpkgs-fmt
          ];
        };
      });

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
