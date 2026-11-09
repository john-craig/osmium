{ pkgs, lib, module, microvm, opencodeNix }:

pkgs.testers.runNixOSTest {
  name = "osmium-opencode-server-live-capture-reverse-configuration";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default ];
    microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "opencap"; mac = "02:00:00:00:00:13"; } ]; shares = lib.mkForce [ ]; };
    system.stateVersion = "25.05";
    nix.settings.trusted-users = [ "root" "opencode" ];
    systemd.tmpfiles.rules = [ "d /run/opencode/credentials 0755 root root -" "f /run/opencode/credentials/server.env 0444 root root - OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=capture-password" "f /run/opencode/credentials/auth.json 0444 root root - {\\\"local\\\":{\\\"type\\\":\\\"api\\\",\\\"key\\\":\\\"capture-token\\\"}}" ];
    services.osmium.opencodeServer = { enable = true; reverseConfiguration.enable = true; credentials.hostDirectory = "/run/opencode/credentials"; };
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
    vm.succeed("systemctl --user -M opencode@ start opencode-web.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.succeed("systemctl --user -M opencode@ set-environment OSMIUM_OPENCODE_RUNTIME_PORT=4101")
    vm.succeed("osmium-opencode-observe > /tmp/capture.json")
    vm.succeed("osmium-opencode-observe > /tmp/capture-repeat.json && cmp /tmp/capture.json /tmp/capture-repeat.json")
    vm.succeed("jq -e '.source.origin == \"observed\" and .server.guest_port == 4101 and .activation_ready == false and .credentials.secrets.excluded == true' /tmp/capture.json")
    vm.succeed("! grep -F capture-password /tmp/capture.json")
  '';
}
