{ pkgs, module, microvm }:

let
  lldapAdminPassword = "lldap-admin-password";
  bindPassword = "authelia-bind-password";
  healthPassword = "health-ldap-password";
  jwtSecret = "authelia-ldap-jwt-secret";
  storageSecret = "authelia-ldap-storage-secret-012345678901234567890";
  sessionSecret = "authelia-ldap-session-secret-012345678901234567890";
in
pkgs.testers.runNixOSTest {
  name = "osmium-lldap-authelia-ldap-authentication";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = { hypervisor = "qemu"; vcpu = 2; mem = 1024; interfaces = [ { type = "user"; id = "lldapauth"; mac = "02:00:00:00:00:93"; } ]; };
    services.osmium.lldap = {
      enable = true;
      baseDn = "dc=example,dc=com";
      httpUrl = "https://lldap.example.invalid";
      admin = { username = "admin"; email = "admin@example.invalid"; passwordFile = "/etc/lldap-admin-password"; };
      jwtSecretFile = "/etc/lldap-jwt";
      keySeedFile = "/etc/lldap-key-seed";
      ldaps.enable = false;
      users.authelia_bind = {
        username = "authelia-bind";
        email = "authelia-bind@example.invalid";
        displayName = "Authelia Bind";
        passwordFile = "/etc/authelia-bind-password";
        consumer = "authelia";
      };
      users.health = {
        username = "health";
        email = "health@example.invalid";
        displayName = "Health User";
        passwordFile = "/etc/health-password";
      };
    };
    services.osmium.authelia = {
      enable = true;
      portalUrl = "https://auth.example.invalid";
      jwtSecretFile = "/etc/authelia-jwt";
      storageEncryptionKeyFile = "/etc/authelia-storage";
      sessionSecretFile = "/etc/authelia-session";
      ldap = {
        enable = true;
        address = "ldap://127.0.0.1:3890";
        baseDn = "dc=example,dc=com";
        bindDn = "uid=authelia-bind,ou=people,dc=example,dc=com";
        bindPasswordFile = "/etc/authelia-bind-password";
        tls.enable = false;
      };
      users.local = {
        username = "local";
        displayName = "Local User";
        email = "local@example.invalid";
        passwordFile = "/etc/local-password";
      };
    };
    environment.etc."lldap-admin-password" = { text = "${lldapAdminPassword}\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-jwt" = { text = "lldap-jwt-secret\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-key-seed" = { text = "lldap-key-seed\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."authelia-bind-password" = { text = "${bindPassword}\n"; mode = "0400"; };
    environment.etc."health-password" = { text = "${healthPassword}\n"; mode = "0400"; };
    environment.etc."local-password" = { text = "local-password\n"; mode = "0400"; };
    environment.etc."authelia-jwt" = { text = "${jwtSecret}\n"; mode = "0400"; };
    environment.etc."authelia-storage" = { text = "${storageSecret}\n"; mode = "0400"; };
    environment.etc."authelia-session" = { text = "${sessionSecret}\n"; mode = "0400"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openldap ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("lldap.service")
    vm.wait_for_unit("osmium-lldap-reconcile.service")
    vm.wait_for_unit("authelia.service")
    vm.wait_for_open_port(9091)
    vm.succeed("curl --fail --silent -H 'Host: auth.example.invalid' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /' -H 'Content-Type: application/json' -d '{\"username\":\"health\",\"password\":\"${healthPassword}\",\"targetURL\":\"https://auth.example.invalid/\"}' http://127.0.0.1:9091/api/firstfactor | jq -e '.status == \"OK\"'")
    vm.succeed("curl --silent --output /dev/null --write-out '%{http_code}' -H 'Host: auth.example.invalid' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /' -H 'Content-Type: application/json' -d '{\"username\":\"local\",\"password\":\"local-password\"}' http://127.0.0.1:9091/api/firstfactor | grep -Fx 401")
    vm.succeed("! grep -R -aF '${healthPassword}' /var/lib/authelia /run/osmium-authelia 2>/dev/null")
    vm.succeed("! grep -R -aF '${bindPassword}' /var/lib/authelia 2>/dev/null")
    vm.shutdown()
  '';
}
