{ pkgs, module, microvm }:

let
  jwtSecret = "authelia-proxy-jwt-secret";
  storageSecret = "authelia-proxy-storage-secret-012345678901234567890";
  sessionSecret = "authelia-proxy-session-secret-012345678901234567890";
in
pkgs.testers.runNixOSTest {
  name = "osmium-authelia-proxy-authorization";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "authelia-proxy"; mac = "02:00:00:00:00:83"; } ];
    };
    services.osmium.authelia = {
      enable = true;
      portalUrl = "https://auth.example.invalid";
      jwtSecretFile = "/etc/authelia-proxy-jwt";
      storageEncryptionKeyFile = "/etc/authelia-proxy-storage";
      sessionSecretFile = "/etc/authelia-proxy-session";
      accessControl = {
        defaultPolicy = "deny";
        rules = [ { domain = "auth.example.invalid"; policy = "one_factor"; } ];
      };
      users.health = {
        username = "health";
        displayName = "Health User";
        email = "health@example.invalid";
        passwordFile = "/etc/health-password";
      };
    };
    environment.etc."authelia-proxy-jwt" = { text = "${jwtSecret}\n"; mode = "0400"; };
    environment.etc."authelia-proxy-storage" = { text = "${storageSecret}\n"; mode = "0400"; };
    environment.etc."authelia-proxy-session" = { text = "${sessionSecret}\n"; mode = "0400"; };
    environment.etc."health-password" = { text = "health-password\n"; mode = "0400"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("authelia.service")
    vm.wait_for_open_port(9091)
    vm.succeed("test \"$(curl --silent --output /dev/null --write-out '%{http_code}' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /private' -H 'X-Forwarded-Method: GET' http://127.0.0.1:9091/api/authz/forward-auth)\" = 302")
    vm.succeed("test \"$(curl --silent --output /dev/null --write-out '%{http_code}' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: other.example.invalid' -H 'X-Forwarded-URI: /private' -H 'X-Forwarded-Method: GET' http://127.0.0.1:9091/api/authz/forward-auth)\" != 200")
    vm.succeed("curl --fail --silent --resolve auth.example.invalid:9091:127.0.0.1 --dump-header /tmp/login.headers --cookie-jar /tmp/authelia.cookies -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /' -H 'Content-Type: application/json' -d '{\"username\":\"health\",\"password\":\"health-password\",\"targetURL\":\"https://auth.example.invalid/private\"}' http://auth.example.invalid:9091/api/firstfactor | jq -e '.status == \"OK\"'")
    vm.succeed("vm_cookie=$(sed -n 's/^[Ss]et-[Cc]ookie: \\([^;]*\\).*/\\1/p' /tmp/login.headers | tr '\\n' ';'); curl --fail --silent --resolve auth.example.invalid:9091:127.0.0.1 --dump-header /tmp/authz.headers --output /tmp/authz.body -H \"Cookie: $vm_cookie\" -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /private' -H 'X-Forwarded-Method: GET' http://auth.example.invalid:9091/api/authz/forward-auth; grep -i '^remote-user: health' /tmp/authz.headers")
    vm.succeed("ss -lnt | grep -E '127\\.0\\.0\\.1:9091|::1:9091'")
    vm.fail("ss -lnt | grep -E '0\\.0\\.0\\.0:9091|\\*:9091'")
    vm.shutdown()
  '';
}
