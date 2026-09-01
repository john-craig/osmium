{
  description = "Reproducible, impermanent NixOS services in MicroVMs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";

    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, impermanence, microvm, sops-nix }:
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

      giteaGuestModules = [
        microvm.nixosModules.microvm
        self.nixosModules.default
        {
          networking.hostName = "mythoclast-gitea";
          system.stateVersion = "25.05";

          microvm = {
            hypervisor = "qemu";
            vcpu = 2;
            mem = 1024;
            interfaces = [ {
              type = "user";
              id = "gitea";
              mac = "02:00:00:00:00:02";
            } ];
          };

          services.mythoclast.gitea = {
            enable = true;
            hostHttpPort = 3001;
            hostSshPort = 2223;
            settings.service.DISABLE_REGISTRATION = false;
          };
        }
      ];
    in
    {
      nixosModules.default = {
        imports = [
          impermanence.nixosModules.impermanence
          sops-nix.nixosModules.sops
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

      nixosConfigurations.gitea-guest = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = giteaGuestModules;
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

          gitea = import ./tests/gitea.nix {
            inherit pkgs microvm;
            lib = nixpkgs.lib;
            module = self.nixosModules.default;
            healthchecks = import ./tests/healthchecks.nix { lib = nixpkgs.lib; };
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
