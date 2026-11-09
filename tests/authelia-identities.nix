{ pkgs, module, microvm }:

let
  jwtSecret = "authelia-identities-jwt-secret";
  storageSecret = "authelia-identities-storage-secret-012345678901234567890";
  sessionSecret = "authelia-identities-session-secret-012345678901234567890";
in
pkgs.testers.runNixOSTest {
  name = "osmium-authelia-identities";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "authelia-id"; mac = "02:00:00:00:00:82"; } ];
    };
    services.osmium.authelia = {
      enable = true;
      portalUrl = "https://auth.example.invalid";
      jwtSecretFile = "/etc/authelia-identities-jwt";
      storageEncryptionKeyFile = "/etc/authelia-identities-storage";
      sessionSecretFile = "/etc/authelia-identities-session";
      totp.defaultMethod = "totp";
      users.health = {
        username = "health";
        displayName = "Health User";
        email = "health@example.invalid";
        passwordFile = "/run/health-password";
        groups = [ "operators" ];
        totp = {
          bootstrapFile = "/run/health-totp-secret";
          outputFile = "/var/lib/authelia/health-totp.png";
        };
      };
      groups.operators = {
        displayName = "Operators";
        users = [ "health" ];
      };
    };
    environment.etc."authelia-identities-jwt" = { text = "${jwtSecret}\n"; mode = "0400"; };
    environment.etc."authelia-identities-storage" = { text = "${storageSecret}\n"; mode = "0400"; };
    environment.etc."authelia-identities-session" = { text = "${sessionSecret}\n"; mode = "0400"; };
    systemd.tmpfiles.rules = [
      "f /run/health-password 0400 root root - health-password"
      "f /run/health-totp-secret 0400 authelia authelia - JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
    ];
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("osmium-authelia-reconcile.service")
    vm.wait_for_unit("authelia.service")
    vm.wait_until_succeeds("systemctl show -p Result --value osmium-authelia-totp-bootstrap.service | grep -Fx success")
    vm.wait_for_open_port(9091)
    vm.succeed("curl --fail --silent --cookie-jar /tmp/authelia.cookies -H 'Host: auth.example.invalid' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /' -H 'Content-Type: application/json' -d '{\"username\":\"health\",\"password\":\"health-password\",\"targetURL\":\"https://auth.example.invalid/\"}' http://127.0.0.1:9091/api/firstfactor | jq -e '.status == \"OK\"'")
    vm.succeed("printf '%s\\n' replacement-password > /run/health-password; systemctl restart osmium-authelia-reconcile.service; sleep 1")
    vm.succeed("test \"$(curl --silent --output /dev/null --write-out '%{http_code}' -H 'Host: auth.example.invalid' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /' -H 'Content-Type: application/json' -d '{\"username\":\"health\",\"password\":\"health-password\"}' http://127.0.0.1:9091/api/firstfactor)\" = 401")
    vm.succeed("curl --fail --silent --cookie-jar /tmp/authelia-new.cookies -H 'Host: auth.example.invalid' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: auth.example.invalid' -H 'X-Forwarded-URI: /' -H 'Content-Type: application/json' -d '{\"username\":\"health\",\"password\":\"replacement-password\",\"targetURL\":\"https://auth.example.invalid/\"}' http://127.0.0.1:9091/api/firstfactor | jq -e '.status == \"OK\"'")
    vm.succeed("jq -e '.users.health.status == \"applied\" and (.users.health.fingerprint | length) == 64 and .users.health.hash == null' /var/lib/authelia/.osmium-authelia.json")
    vm.succeed("jq -e '.totp.health == true' /var/lib/authelia/.osmium-authelia.json; test -s /var/lib/authelia/health-totp.png")
    vm.succeed("before=$(sha256sum /var/lib/authelia/health-totp.png | cut -d' ' -f1); systemctl restart osmium-authelia-totp-bootstrap.service; test \"$(sha256sum /var/lib/authelia/health-totp.png | cut -d' ' -f1)\" = \"$before\"")
    vm.succeed("! grep -R -aF 'replacement-password' /var/lib/authelia /run/osmium-authelia 2>/dev/null")
    vm.succeed("! grep -R -aF '${jwtSecret}' /var/lib/authelia /run/osmium-authelia 2>/dev/null")
    vm.shutdown()
  '';
}
