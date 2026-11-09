{ pkgs, module, microvm }:
let
  fixture = import ./fdroid-repository-fixture.nix { inherit pkgs; };
in pkgs.testers.runNixOSTest {
  name = "osmium-fdroid-repository-drift-reverse-configuration";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "fdroid-drift"; mac = "02:00:00:00:00:0d"; } ]; };
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
        printf 'drift-secret-password\n' > /run/fdroid/password
        ${pkgs.jdk}/bin/keytool -genkeypair -keystore /run/fdroid/keystore -storepass drift-secret-password -keypass drift-secret-password -alias fdroid -dname CN=fdroid -keyalg RSA -validity 3650 -noprompt
        chmod 0400 /run/fdroid/password /run/fdroid/keystore; chown -R fdroid:fdroid /run/fdroid
      '';
    };
    services.osmium.fdroidRepository = fixture.base;
  };
  testScript = ''
    vm.start()
    vm.wait_for_unit("osmium-fdroid-repository.service")
    vm.wait_for_open_port(8080)
    vm.succeed("curl --fail http://127.0.0.1:8080/repo/index-v2.json >/tmp/index.json")
    vm.succeed("cp /var/lib/fdroid-repository/repo/org.osmium.test_1.apk /var/lib/fdroid-repository/repo/org.osmium.drift_2.apk")
    vm.succeed("sha=$(sha256sum /var/lib/fdroid-repository/repo/org.osmium.drift_2.apk | cut -d' ' -f1); jq --arg sha \"$sha\" '.name=\"Externally changed\" | .description=\"Changed at runtime\" | .artifacts += [{package:\"org.osmium.drift\",version_code:2,version_name:\"2.0\",sha256:$sha,path:\"/var/lib/fdroid-repository/repo/org.osmium.drift_2.apk\",file:\"org.osmium.drift_2.apk\"}]' /var/lib/fdroid-repository/ledger.json >/tmp/ledger.json && mv /tmp/ledger.json /var/lib/fdroid-repository/ledger.json")
    vm.succeed("sha256sum /var/lib/fdroid-repository/ledger.json >/tmp/ledger-before.sha256")
    vm.succeed("osmium-fdroid-repository drift --output /tmp/drift.json && osmium-fdroid-repository convert --input /tmp/drift.json --output /tmp/candidate.json")
    vm.succeed("osmium-fdroid-repository convert --input /tmp/drift.json --output /tmp/candidate-repeat.json && cmp /tmp/candidate.json /tmp/candidate-repeat.json")
    vm.succeed("jq -e '.complete and .activation_ready and .fdroidRepository.name == \"Externally changed\" and .fdroidRepository.artifacts.org_osmium_drift.sha256 != null' /tmp/candidate.json")
    vm.succeed("osmium-fdroid-repository validate --input /tmp/candidate.json && osmium-fdroid-repository reconcile --input /tmp/candidate.json --output /tmp/reconciled.json")
    vm.succeed("jq -e '.declaration == \"x\"' /tmp/reconciled.json >/dev/null || jq -e '.declaration.name == \"Externally changed\"' /tmp/reconciled.json")
    vm.succeed("sha256sum -c /tmp/ledger-before.sha256")
    vm.succeed("! grep -E -i 'drift-secret-password|private.key|keystorepass' /tmp/drift.json /tmp/candidate.json /tmp/reconciled.json")
    vm.succeed("jq 'del(.repository.signing)' /tmp/drift.json >/tmp/incomplete.json && osmium-fdroid-repository convert --input /tmp/incomplete.json --output /tmp/incomplete-candidate.json && ! osmium-fdroid-repository validate --input /tmp/incomplete-candidate.json")
  '';
}
