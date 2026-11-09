{ pkgs, lib, module, microvm, opencodeNix }:

pkgs.testers.runNixOSTest {
  name = "osmium-opencode-server-profiles-live-capture-reverse-configuration";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default ];
    microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "ocpcap"; mac = "02:00:00:00:00:17"; } ]; shares = lib.mkForce [ ]; };
    system.stateVersion = "25.05";
    nix.settings.trusted-users = [ "root" "opencode" ];
    systemd.tmpfiles.rules = [ "d /run/opencode/credentials 0755 root root -" "f /run/opencode/credentials/server.env 0444 root root - OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=capture-profile-password" "f /run/opencode/credentials/auth.json 0444 root root - {\\\"local\\\":{\\\"type\\\":\\\"api\\\",\\\"key\\\":\\\"capture-profile-token\\\"}}" ];
    services.osmium.opencodeServer = {
      enable = true;
      reverseConfiguration.enable = true;
      credentials.hostDirectory = "/run/opencode/credentials";
       skills.facts.path = pkgs.writeTextDir "facts/SKILL.md" "capture skill\n";
       mcpServers.remote = { type = "remote"; url = "https://example.invalid/mcp"; };
       profiles.facts = { model = "local/mock"; rules = [ "capture-profile-rule" ]; skills = [ "facts" ]; mcpServers = [ "remote" ]; };
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
    vm.succeed("osmium-opencode-observe > /tmp/profile-capture.json")
    vm.succeed("osmium-opencode-observe > /tmp/profile-capture-repeat.json && cmp /tmp/profile-capture.json /tmp/profile-capture-repeat.json")
    vm.succeed("jq -e '.schema_version == 2 and .source.origin == \"observed\" and .source.scope == \"guest-runtime\" and (.profiles | keys) == [\"facts\"] and .profiles.facts.enable == true and .profiles.facts.model == \"local/mock\" and .profiles.facts.rules[0] == \"capture-profile-rule\" and (.profiles.facts.skills | index(\"facts\")) != null and (.profiles.facts.mcpServers | index(\"remote\")) != null and (.profiles.facts.permissions | type) == \"object\" and .credentials.secrets.excluded == true and .complete == false and .activation_ready == false' /tmp/profile-capture.json")
    vm.succeed("! grep -E -i 'capture-profile-password|capture-profile-token' /tmp/profile-capture.json")
  '';
}
