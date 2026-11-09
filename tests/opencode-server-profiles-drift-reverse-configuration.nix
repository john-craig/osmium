{ pkgs, lib, module, microvm, opencodeNix }:

pkgs.testers.runNixOSTest {
  name = "osmium-opencode-server-profiles-drift-reverse-configuration";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default ];
    microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "ocpdrift"; mac = "02:00:00:00:00:16"; } ]; shares = lib.mkForce [ ]; };
    system.stateVersion = "25.05";
    nix.settings.trusted-users = [ "root" "opencode" ];
    systemd.tmpfiles.rules = [ "d /run/opencode/credentials 0755 root root -" "f /run/opencode/credentials/server.env 0444 root root - OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=drift-profile-password" "f /run/opencode/credentials/auth.json 0444 root root - {\\\"local\\\":{\\\"type\\\":\\\"api\\\",\\\"key\\\":\\\"drift-profile-token\\\"}}" ];
    services.osmium.opencodeServer = {
      enable = true;
      reverseConfiguration.enable = true;
      credentials.hostDirectory = "/run/opencode/credentials";
      profiles.facts = { model = "local/mock"; rules = [ "runtime-profile-rule" ]; };
    };
    systemd.services.home-manager-opencode.requires = lib.mkForce [ ];
    systemd.services.home-manager-opencode.after = lib.mkForce [ ];
    environment.systemPackages = [ pkgs.jq ];
  };
  testScript = ''
    vm.start()
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.succeed("systemctl stop osmium-opencode-reconcile.timer")
    vm.succeed("systemd-run --unit=osmium-test-nix-daemon --service-type=simple nix-daemon --daemon")
    vm.wait_for_file("/nix/var/nix/daemon-socket/socket")
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.wait_for_unit("user@1984.service")
    vm.succeed("jq '.agent.facts.model = \"local/drifted\"' /var/lib/opencode/.config/opencode/opencode.json > /tmp/opencode.json && mv /tmp/opencode.json /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("osmium-opencode-drift > /tmp/profile-drift.json")
    vm.succeed("jq -e '.drift == true and (.profiles | keys) == [\"facts\"] and .profiles.facts.enable == true and .profiles.facts.model == \"local/drifted\" and (.profiles.facts.permissions | type) == \"object\" and .candidate.complete == false and .candidate.activation_ready == false and .candidate.provenance.review_only == true and (.candidate.findings | map(.code) | index(\"profile-source-unresolved\")) != null' /tmp/profile-drift.json")
    vm.succeed("! grep -E -i 'drift-profile-password|drift-profile-token' /tmp/profile-drift.json")
  '';
}
