{
  description = "Reproducible, impermanent NixOS services in MicroVMs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    opencode-nix.url = "github:albertov/opencode-nix";
    opencode-nix.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";

    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, opencode-nix, impermanence, microvm, sops-nix }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      guestModules = [
        microvm.nixosModules.microvm
        self.nixosModules.default
        {
           networking.hostName = "osmium-demo";
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

           services.osmium.hello = {
            enable = true;
            port = 8080;
          };
        }
      ];

      giteaGuestModules = [
        microvm.nixosModules.microvm
        self.nixosModules.default
        {
           networking.hostName = "osmium-gitea";
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

           services.osmium.gitea = {
            enable = true;
            hostHttpPort = 3001;
            hostSshPort = 2223;
            settings.service.DISABLE_REGISTRATION = false;
          };
        }
      ];

      fdroidGuestModules = [
        microvm.nixosModules.microvm
        self.nixosModules.default
        {
          networking.hostName = "osmium-fdroid";
          system.stateVersion = "25.05";
          microvm = {
            hypervisor = "qemu";
            vcpu = 1;
            mem = 512;
            interfaces = [ { type = "user"; id = "fdroid"; mac = "02:00:00:00:00:0b"; } ];
          };
        }
      ];
    in
    {
      nixosModules.default = {
          imports = [
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            { nixpkgs.overlays = nixpkgs.lib.mkDefault [ opencode-nix.overlays.default ]; }
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
             osmium.host = {
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

      nixosConfigurations.fdroid-guest = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = fdroidGuestModules;
      };

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          rebrand = import ./tests/rebrand.nix {
            inherit pkgs microvm;
            lib = nixpkgs.lib;
            module = self.nixosModules.default;
          };
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

          filesystem-snapshot-module = import ./tests/filesystem-snapshot-module.nix {
            inherit pkgs;
            lib = nixpkgs.lib;
            module = self.nixosModules.default;
          };

          filesystem-snapshot-persistence = import ./tests/filesystem-snapshot-persistence.nix {
            inherit pkgs microvm;
            module = self.nixosModules.default;
          };

          filesystem-snapshot-drift = import ./tests/filesystem-snapshot-drift.nix {
            inherit pkgs microvm;
            module = self.nixosModules.default;
          };

            gitea = import ./tests/gitea.nix {
            inherit pkgs microvm;
            lib = nixpkgs.lib;
            module = self.nixosModules.default;
             healthchecks = import ./tests/healthchecks.nix { lib = nixpkgs.lib; };
            };

            gitea-credentials = import ./tests/gitea-credentials.nix {
              inherit pkgs microvm;
              lib = nixpkgs.lib;
              module = self.nixosModules.default;
            };

            remote-gitea-capture = import ./tests/remote-gitea-capture.nix {
             inherit pkgs microvm;
             module = self.nixosModules.default;
           };

            remote-gitea-capture-real = import ./tests/remote-gitea-capture-real.nix {
             inherit pkgs microvm;
             module = self.nixosModules.default;
            };

           gitea-repository-drift-reverse-configuration = import ./tests/gitea-repository-drift-reverse-configuration.nix {
             inherit pkgs microvm;
             module = self.nixosModules.default;
           };

            gitea-repository-live-capture-reverse-configuration = import ./tests/gitea-repository-live-capture-reverse-configuration.nix {
             inherit pkgs microvm;
             module = self.nixosModules.default;
            };

            fdroid-repository = import ./tests/fdroid-repository.nix {
              inherit pkgs microvm;
              lib = nixpkgs.lib;
              module = self.nixosModules.default;
            };

            fdroid-repository-drift-reverse-configuration = import ./tests/fdroid-repository-drift-reverse-configuration.nix {
              inherit pkgs microvm;
              module = self.nixosModules.default;
            };

           fdroid-repository-live-capture-reverse-configuration = import ./tests/fdroid-repository-live-capture-reverse-configuration.nix {
               inherit pkgs microvm;
               module = self.nixosModules.default;
              };

              opencode-server = import ./tests/opencode-server.nix {
                inherit pkgs microvm;
                opencodeNix = opencode-nix;
                lib = nixpkgs.lib;
                module = self.nixosModules.default;
              };

              opencode-server-drift-reverse-configuration = import ./tests/opencode-server-drift-reverse-configuration.nix {
                inherit pkgs microvm;
                opencodeNix = opencode-nix;
                lib = nixpkgs.lib;
                module = self.nixosModules.default;
              };

              opencode-server-live-capture-reverse-configuration = import ./tests/opencode-server-live-capture-reverse-configuration.nix {
                inherit pkgs microvm;
                opencodeNix = opencode-nix;
                lib = nixpkgs.lib;
                module = self.nixosModules.default;
              };

               opencode-server-profiles = import ./tests/opencode-server-profiles.nix {
                inherit pkgs microvm;
                opencodeNix = opencode-nix;
                lib = nixpkgs.lib;
                module = self.nixosModules.default;
               };

               opencode-server-profiles-evaluation = import ./tests/opencode-server-profiles-evaluation.nix {
                 inherit pkgs microvm;
                 opencodeNix = opencode-nix;
                 lib = nixpkgs.lib;
                 module = self.nixosModules.default;
               };

              opencode-server-profiles-drift-reverse-configuration = import ./tests/opencode-server-profiles-drift-reverse-configuration.nix {
                inherit pkgs microvm;
                opencodeNix = opencode-nix;
                lib = nixpkgs.lib;
                module = self.nixosModules.default;
              };

              opencode-server-profiles-live-capture-reverse-configuration = import ./tests/opencode-server-profiles-live-capture-reverse-configuration.nix {
                inherit pkgs microvm;
                opencodeNix = opencode-nix;
                lib = nixpkgs.lib;
                module = self.nixosModules.default;
              };

             gitea-fdroid-action-publish = import ./tests/gitea-fdroid-action-publish.nix {
               inherit pkgs microvm;
               lib = nixpkgs.lib;
               module = self.nixosModules.default;
             };

           osmium-rebrand-fresh = rebrand.osmium-rebrand-fresh;
          osmium-rebrand-migration = rebrand.osmium-rebrand-migration;
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
