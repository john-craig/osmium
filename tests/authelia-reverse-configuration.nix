{ pkgs, module, microvm, mode }:

let
  jwtSecret = "authelia-reverse-jwt-secret";
  storageSecret = "authelia-reverse-storage-secret-012345678901234567890";
  sessionSecret = "authelia-reverse-session-secret-012345678901234567890";
in
pkgs.testers.runNixOSTest {
  name = "osmium-authelia-${mode}-reverse-configuration";
  nodes = {
    source = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; vcpu = 2; mem = 768; interfaces = [ { type = "user"; id = "authrevsrc"; mac = "02:00:00:00:00:91"; } ]; };
      services.osmium.authelia = {
        enable = true;
        reverseConfiguration.enable = true;
        portalUrl = "https://auth.example.invalid";
        jwtSecretFile = "/etc/authelia-reverse-jwt";
        storageEncryptionKeyFile = "/etc/authelia-reverse-storage";
        sessionSecretFile = "/etc/authelia-reverse-session";
        users.health = { username = "health"; displayName = "Health User"; email = "health@example.invalid"; passwordFile = "/etc/health-password"; };
      };
      environment.etc."authelia-reverse-jwt" = { text = "${jwtSecret}\n"; mode = "0400"; };
      environment.etc."authelia-reverse-storage" = { text = "${storageSecret}\n"; mode = "0400"; };
      environment.etc."authelia-reverse-session" = { text = "${sessionSecret}\n"; mode = "0400"; };
      environment.etc."health-password" = { text = "health-password\n"; mode = "0400"; };
      environment.systemPackages = [ pkgs.curl pkgs.jq ];
    };
    replay = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; vcpu = 2; mem = 768; interfaces = [ { type = "user"; id = "authrevrep"; mac = "02:00:00:00:00:92"; } ]; };
      services.osmium.authelia = {
        enable = true;
        reverseConfiguration.enable = true;
        portalUrl = "https://auth.example.invalid";
        jwtSecretFile = "/etc/authelia-reverse-jwt";
        storageEncryptionKeyFile = "/etc/authelia-reverse-storage";
        sessionSecretFile = "/etc/authelia-reverse-session";
        users.captured = { username = "captured"; displayName = "Captured User"; email = "captured@example.invalid"; passwordFile = "/etc/captured-password"; };
      };
      environment.etc."authelia-reverse-jwt" = { text = "${jwtSecret}\n"; mode = "0400"; };
      environment.etc."authelia-reverse-storage" = { text = "${storageSecret}\n"; mode = "0400"; };
      environment.etc."authelia-reverse-session" = { text = "${sessionSecret}\n"; mode = "0400"; };
      environment.etc."captured-password" = { text = "captured-password\n"; mode = "0400"; };
      environment.systemPackages = [ pkgs.curl pkgs.jq ];
    };
  };
  testScript = ''
    start_all()
    source.wait_for_unit("authelia.service")
    source.wait_for_unit("osmium-authelia-reconcile.service")
    replay.wait_for_unit("authelia.service")
    source.succeed("osmium-authelia-observe --output /tmp/before.json")
    source.succeed("ledger_before=$(sha256sum /var/lib/authelia/.osmium-authelia.json | cut -d' ' -f1); hash=$(jq -r '.users.health.password' /var/lib/authelia/users.yml); jq --arg hash \"$hash\" '.users.captured={disabled:false,displayname:\"Captured User\",email:\"captured@example.invalid\",password:$hash,groups:[]}' /var/lib/authelia/users.yml > /tmp/users.yml; mv /tmp/users.yml /var/lib/authelia/users.yml; osmium-authelia-observe --output /tmp/after.json; test \"$(sha256sum /var/lib/authelia/.osmium-authelia.json | cut -d' ' -f1)\" = \"$ledger_before\"; osmium-authelia-drift --observation /tmp/after.json --declared <(jq '.declaration.services.osmium.authelia' /tmp/before.json) --output /tmp/drift.json; jq -e '.changes | any(.[]; .resource == \"user\" and .name == \"captured\" and .kind == \"unmanaged\")' /tmp/drift.json; ! grep -E -i '${jwtSecret}|${storageSecret}|${sessionSecret}' /tmp/before.json /tmp/after.json /tmp/drift.json")
    source.succeed("osmium-authelia-candidate --input /tmp/after.json > /tmp/candidate.json; jq -e '.complete == false and .activation_ready == false and .declaration.services.osmium.authelia.users.captured.passwordFile.unresolved == true' /tmp/candidate.json")
    candidate_b64 = source.succeed("base64 -w0 /tmp/candidate.json").strip()
    replay.succeed("printf '%s' '" + candidate_b64 + "' | base64 -d > /tmp/candidate.json; jq -e '.declaration.services.osmium.authelia.users.captured.username == \"captured\" and .secrets.excluded == true' /tmp/candidate.json")
    source.succeed("osmium-authelia-observe --capture --output /tmp/capture.json; jq -e '.source.origin == \"live-capture\" and (.users | any(.username == \"captured\")) and .complete == false' /tmp/capture.json")
    source.shutdown()
    replay.shutdown()
  '';
}
