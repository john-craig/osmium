{ pkgs, lib, module }:

let
  base = {
    system.stateVersion = "25.05";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
    services.osmium.keycloak = {
      enable = true;
      allowInsecureHttp = true;
      issuer = "http://127.0.0.1:8080";
      admin.passwordFile = "/run/keycloak-admin-password";
      database.passwordFile = "/run/keycloak-database-password";
      realms.example = { name = "example"; };
      clients.lldap = {
        realm = "example";
        clientId = "lldap";
        secretFile = "/run/lldap-client-secret";
        redirectUris = [ "https://lldap.example.invalid/oauth2/callback" ];
      };
    };
    services.osmium.lldap = {
      enable = true;
      admin.passwordFile = "/run/lldap-admin-password";
      jwtSecretFile = "/run/lldap-jwt-secret";
      keySeedFile = "/run/lldap-key-seed";
      gateway = {
        enable = true;
        keycloak = { realm = "example"; client = "lldap"; };
        callbackUrl = "https://lldap.example.invalid/oauth2/callback";
        clientSecretFile = "/run/lldap-client-secret";
        cookieSecretFile = "/run/lldap-cookie-secret";
        tls = { certificateFile = "/run/lldap-certificate.pem"; keyFile = "/run/lldap-key.pem"; };
        operator.allowedEmails = [ "operator@example.com" ];
      };
      users.alice = {
        username = "alice";
        email = "alice@example.com";
        passwordFile = "/run/alice-password";
        groups = [ "readers" ];
      };
      groups.readers = { displayName = "readers"; users = [ "alice" ]; };
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
assert !evaluates { services.osmium.lldap.baseDn = "example.com"; };
assert !evaluates { services.osmium.lldap.httpUrl = "http://lldap.example.invalid"; };
assert !evaluates { services.osmium.lldap.stateDir = "/var/lib/other"; };
assert !evaluates { services.osmium.lldap.hostLdapPort = 17170; services.osmium.lldap.hostHttpPort = 17170; };
assert !evaluates { services.osmium.lldap.users.alice.username = "bad name"; };
assert !evaluates { services.osmium.lldap.users.alice.passwordFile = "/nix/store/password"; };
assert !evaluates { services.osmium.lldap.users.alice.groups = [ "missing" ]; };
assert !evaluates { services.osmium.lldap.groups.readers.users = [ "missing" ]; };
assert !evaluates { services.osmium.lldap.users.bob = { username = "alice"; email = "bob@example.com"; passwordFile = "/run/bob-password"; }; };
assert !evaluates { services.osmium.lldap.groups.other = { displayName = "readers"; }; };
assert !evaluates { services.osmium.lldap.gateway.callbackUrl = "http://lldap.example.invalid/oauth2/callback"; };
assert !evaluates { services.osmium.lldap.gateway.operator.allowedEmails = lib.mkForce [ ]; services.osmium.lldap.gateway.operator.allowedGroups = lib.mkForce [ ]; };
assert !evaluates { services.osmium.lldap.gateway.clientSecretFile = "/nix/store/client-secret"; };
assert !evaluates { services.osmium.lldap.gateway.keycloak.client = "missing"; };
pkgs.runCommand "osmium-lldap-module-evaluation" { } ''
  touch $out
''
