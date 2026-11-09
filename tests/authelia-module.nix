{ pkgs, lib, module }:

let
  base = {
    system.stateVersion = "25.05";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
    services.osmium.authelia = {
      enable = true;
      jwtSecretFile = "/run/authelia-jwt";
      storageEncryptionKeyFile = "/run/authelia-storage";
      sessionSecretFile = "/run/authelia-session";
      users.alice = {
        username = "alice";
        displayName = "Alice";
        email = "alice@example.com";
        passwordFile = "/run/alice-password";
        groups = [ "users" ];
      };
      groups.users = { displayName = "users"; users = [ "alice" ]; };
    };
  };
  evaluates = extra: (builtins.tryEval (
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ module base extra ];
    }).config.system.build.toplevel
  )).success;
in
assert evaluates { };
assert !evaluates { services.osmium.authelia.portalUrl = "http://auth.example.invalid"; };
assert !evaluates { services.osmium.authelia.listenAddress = "0.0.0.0"; };
assert !evaluates { services.osmium.authelia.stateDir = "/var/lib/other"; };
assert !evaluates { services.osmium.authelia.users.alice.groups = [ "missing" ]; };
assert !evaluates { services.osmium.authelia.groups.users.users = [ "missing" ]; };
assert !evaluates { services.osmium.authelia.users.bob = { username = "alice"; email = "bob@example.com"; passwordFile = "/run/bob-password"; }; };
assert !evaluates { services.osmium.authelia.users.alice.passwordFile = "/nix/store/password"; };
assert !evaluates { services.osmium.authelia.ldap.enable = true; };
assert !evaluates { services.osmium.authelia.ldap.tls.enable = true; };
pkgs.runCommand "osmium-authelia-module-evaluation" { } ''
  touch $out
''
