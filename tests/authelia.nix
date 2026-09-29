{ pkgs, module, microvm }:

let
  jwtSecret = "authelia-jwt-secret-value";
  storageSecret = "authelia-storage-secret-value-012345678901234567890123";
  sessionSecret = "authelia-session-secret-value-012345678901234567890123";
in
pkgs.testers.runNixOSTest {
  name = "osmium-authelia";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "autheliavm"; mac = "02:00:00:00:00:81"; } ];
    };
    services.osmium.authelia = {
      enable = true;
      portalUrl = "https://auth.example.invalid";
      hostPort = 19091;
      jwtSecretFile = "/etc/authelia-jwt";
      storageEncryptionKeyFile = "/etc/authelia-storage";
      sessionSecretFile = "/etc/authelia-session";
      users.health = {
        username = "health";
        displayName = "Health User";
        email = "health@example.invalid";
        passwordFile = "/etc/health-password";
      };
    };
    environment.etc."authelia-jwt" = { text = "${jwtSecret}\n"; mode = "0400"; };
    environment.etc."authelia-storage" = { text = "${storageSecret}\n"; mode = "0400"; };
    environment.etc."authelia-session" = { text = "${sessionSecret}\n"; mode = "0400"; };
    environment.etc."health-password" = { text = "health-password\n"; mode = "0400"; };
    environment.systemPackages = [ pkgs.curl pkgs.iproute2 pkgs.jq ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("osmium-authelia-runtime-environment.service")
    vm.wait_for_unit("osmium-authelia-reconcile.service")
    vm.wait_for_unit("authelia.service")
    vm.wait_for_open_port(9091)
    vm.succeed("curl --fail --silent http://127.0.0.1:9091/api/health | grep -F 'OK'")
    vm.succeed("ss -lnt | grep -E '127\\.0\\.0\\.1:9091|::1:9091'")
    vm.fail("ss -lnt | grep -E '0\\.0\\.0\\.0:9091|\\*:9091'")
    vm.succeed("test -s /var/lib/authelia/db.sqlite3")
    vm.succeed("test -s /var/lib/authelia/users.yml")
    vm.succeed("jq -e '.users.health.displayname == \"Health User\" and .users.health.email == \"health@example.invalid\" and (.users.health.password | startswith(\"$argon2\"))' /var/lib/authelia/users.yml")
    vm.succeed("jq -e '.users.health.hash == null and (.users.health.fingerprint | length) == 64' /var/lib/authelia/.osmium-authelia.json")
    vm.succeed("! grep -R -aF 'health-password' /var/lib/authelia /run/osmium-authelia /nix/store 2>/dev/null")
    vm.succeed("! grep -R -aF '${jwtSecret}' /var/lib/authelia /run/osmium-authelia /nix/store 2>/dev/null")
    vm.succeed("! grep -aF '${storageSecret}' /proc/$(systemctl show -p MainPID --value authelia.service)/cmdline /var/lib/authelia/.osmium-authelia.json")
    vm.succeed("before=$(sha256sum /var/lib/authelia/db.sqlite3 | cut -d' ' -f1); systemctl restart authelia.service; test \"$(sha256sum /var/lib/authelia/db.sqlite3 | cut -d' ' -f1)\" = \"$before\"")
    vm.succeed("systemctl is-active authelia.service")
    vm.shutdown()
  '';
}
