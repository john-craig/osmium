{ pkgs, module, microvm }:
let
  fixture = import ./fdroid-repository-fixture.nix { inherit pkgs; };
in pkgs.testers.runNixOSTest {
  name = "osmium-fdroid-repository-live-capture-reverse-configuration";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "fdroid-capture"; mac = "02:00:00:00:00:0e"; } ]; };
    virtualisation.graphics = false;
    virtualisation.diskSize = 2048;
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; options = [ "mode=755" ]; neededForBoot = true; };
    fileSystems."/persistent" = { device = "/dev/vda"; fsType = "ext4"; neededForBoot = true; };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
    systemd.services.fdroid-test-secret = {
      before = [ "osmium-fdroid-repository-generate.service" ]; wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        install -d -m 0700 /run/fdroid
        printf 'capture-secret-password\n' > /run/fdroid/password
        ${pkgs.jdk}/bin/keytool -genkeypair -keystore /run/fdroid/keystore -storepass capture-secret-password -keypass capture-secret-password -alias fdroid -dname CN=fdroid -keyalg RSA -validity 3650 -noprompt
        chmod 0400 /run/fdroid/password /run/fdroid/keystore; chown -R fdroid:fdroid /run/fdroid
      '';
    };
    services.osmium.fdroidRepository = fixture.base;
  };
  testScript = ''
    vm.start()
    vm.wait_for_unit("osmium-fdroid-repository.service")
    vm.succeed("cp /var/lib/fdroid-repository/repo/org.osmium.test_1.apk /var/lib/fdroid-repository/repo/org.osmium.capture_3.apk")
    vm.succeed("sha=$(sha256sum /var/lib/fdroid-repository/repo/org.osmium.capture_3.apk | cut -d' ' -f1); jq --arg sha \"$sha\" '.description=\"Captured runtime repository\" | .artifacts += [{package:\"org.osmium.capture\",version_code:3,version_name:\"3.0\",sha256:$sha,path:\"/var/lib/fdroid-repository/repo/org.osmium.capture_3.apk\",file:\"org.osmium.capture_3.apk\"}]' /var/lib/fdroid-repository/ledger.json >/tmp/ledger.json && mv /tmp/ledger.json /var/lib/fdroid-repository/ledger.json")
    vm.succeed("sha256sum /var/lib/fdroid-repository/ledger.json >/tmp/capture-before.sha256")
    vm.succeed("osmium-fdroid-repository capture --output /tmp/capture.json && osmium-fdroid-repository capture --output /tmp/capture-repeat.json && cmp /tmp/capture.json /tmp/capture-repeat.json")
    vm.succeed("osmium-fdroid-repository convert --input /tmp/capture.json --output /tmp/capture-candidate.json && osmium-fdroid-repository reconcile --input /tmp/capture-candidate.json --output /tmp/capture-reconciled.json")
    vm.succeed("jq -e '.source.kind == \"live-capture\" and .complete and .fdroidRepository.description == \"Captured runtime repository\" and .fdroidRepository.artifacts.org_osmium_capture.sha256 != null' /tmp/capture-candidate.json")
    vm.succeed("jq -e '.declaration.description == \"Captured runtime repository\"' /tmp/capture-reconciled.json")
    vm.succeed("sha256sum -c /tmp/capture-before.sha256")
    vm.succeed("! grep -E -i 'capture-secret-password|private.key|keystorepass' /tmp/capture.json /tmp/capture-candidate.json /tmp/capture-reconciled.json")
    vm.succeed("jq 'del(.repository.base_url)' /tmp/capture.json >/tmp/partial.json && osmium-fdroid-repository convert --input /tmp/partial.json --output /tmp/partial-candidate.json && ! osmium-fdroid-repository validate --input /tmp/partial-candidate.json")
  '';
}
