{ pkgs, lib, microvm, module }:

let
  conflictingNamespaces = (builtins.tryEval ((lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ module {
      services.osmium.hello = { enable = true; port = 8080; };
      services.mythoclast.hello.port = 8081;
    } ];
  }).config.system.build.toplevel)).success;

  common = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    virtualisation.graphics = false;
    virtualisation.diskSize = 4096;
    microvm = {
      hypervisor = "qemu";
      interfaces = [ {
        type = "user";
        id = "rebrand";
        mac = "02:00:00:00:00:04";
      } ];
    };
    system.stateVersion = "25.05";
    environment.systemPackages = with pkgs; [ curl jq ];
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "mode=755" ];
      neededForBoot = true;
    };
    fileSystems."/persistent" = {
      device = "/dev/vda";
      fsType = "ext4";
      neededForBoot = true;
    };
  };

  serviceConfig = {
    services.osmium.hello = { enable = true; port = 8080; };
    services.osmium.gitea = {
      enable = true;
      admin.enable = true;
      admin.passwordFile = "/etc/gitea-admin-password";
    };
    environment.etc."gitea-admin-password" = {
      text = "test-admin-password\n";
      mode = "0400";
      user = "gitea";
      group = "gitea";
    };
  };

  snapshot = {
    services.osmium.filesystemSnapshot = {
      enable = true;
      trackers.test = {
        source = "/var/lib/osmium-snapshot/source";
        snapshotRoot = "/var/lib/osmium-snapshot/root";
      };
    };
  };

  legacySnapshotPersistence = {
    environment.persistence."/persistent".directories = lib.mkAfter [
      { directory = "/var/lib/osmium-snapshot/root/.mythoclast"; }
    ];
  };

  fresh = pkgs.testers.runNixOSTest {
    name = "osmium-rebrand-fresh";
    nodes.vm = lib.recursiveUpdate common (lib.recursiveUpdate serviceConfig snapshot);
    testScript = ''
      vm.start(allow_reboot=True)
      vm.wait_for_unit("osmium-hello.service")
      vm.wait_for_unit("gitea.service")
      vm.wait_for_unit("osmium-gitea-admin-bootstrap.service")
      vm.wait_for_open_port(8080)
      vm.wait_for_open_port(3000)
      vm.succeed("curl --fail http://127.0.0.1:8080/")
      vm.succeed("test -x /run/current-system/sw/bin/osmium-gitea-drift || true")
      vm.succeed("test -x /run/current-system/sw/bin/osmium-filesystem-snapshot")
      vm.succeed("systemctl list-unit-files osmium-hello.service osmium-filesystem-snapshot-test-baseline.service")
      vm.succeed("systemctl is-active mythoclast-hello.service")
      vm.succeed("test -d /var/lib/osmium-hello && test -d /var/lib/osmium-snapshot/root/.osmium")
      vm.succeed("printf fresh-state > /var/lib/osmium-hello/state")
      vm.succeed("systemctl restart osmium-hello.service")
      vm.succeed("test \"$(cat /var/lib/osmium-hello/state)\" = fresh-state")
      vm.succeed("test ! -e /var/lib/osmium-migration/.state-v1-complete || test -e /var/lib/osmium-migration/.state-v1-complete")
    '';
  };

  migration = pkgs.testers.runNixOSTest {
    name = "osmium-rebrand-migration";
    nodes.vm = lib.recursiveUpdate common (lib.recursiveUpdate serviceConfig (lib.recursiveUpdate snapshot legacySnapshotPersistence));
    testScript = ''
      vm.start(allow_reboot=True)
      vm.wait_for_unit("osmium-hello.service")
      vm.wait_for_unit("gitea.service")
      vm.wait_for_unit("osmium-gitea-admin-bootstrap.service")
      vm.succeed("curl --fail --user admin:test-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
      vm.succeed("curl --fail --user admin:test-admin-password -X POST http://127.0.0.1:3000/api/v1/user/repos -H 'Content-Type: application/json' -d '{\"name\":\"migration\"}'")
      vm.succeed("printf before-migration > /var/lib/osmium-hello/state")
      vm.succeed("install -d /var/lib/osmium-snapshot/root/.mythoclast/snapshots; printf '{\"current_baseline\":\"legacy\",\"active_references\":[]}' > /var/lib/osmium-snapshot/root/.mythoclast/state.json; printf '{\"metadata\":{\"schema\":\"mythoclast.filesystem.snapshot-metadata\"}}' > /var/lib/osmium-snapshot/root/.mythoclast/snapshots/legacy.json")
      vm.succeed("systemctl stop osmium-hello.service; umount /var/lib/osmium-hello; rm -rf /var/lib/osmium-hello /persistent/var/lib/osmium-hello; mkdir /var/lib/mythoclast-hello; printf before-migration > /var/lib/mythoclast-hello/state")
      vm.succeed("umount /var/lib/osmium-snapshot/root/.osmium/reports /var/lib/osmium-snapshot/root/.osmium/cache /var/lib/osmium-snapshot/root/.osmium; rm -rf /persistent/var/lib/osmium-snapshot/root/.osmium")
      vm.succeed("rm /var/lib/osmium-migration/.state-v1-complete; touch /var/lib/gitea/.mythoclast-admin-bootstrap-complete; rm -f /var/lib/gitea/.osmium-admin-bootstrap-complete")
      vm.reboot()
      vm.wait_for_unit("osmium-hello.service")
      vm.wait_for_unit("gitea.service")
      vm.succeed("test \"$(cat /var/lib/osmium-hello/state)\" = before-migration")
      vm.succeed("test -d /var/lib/mythoclast-hello && test -e /var/lib/osmium-migration/.state-v1-complete")
      vm.succeed("test -e /var/lib/gitea/.osmium-admin-bootstrap-complete && test -e /var/lib/gitea/.mythoclast-admin-bootstrap-complete")
      vm.succeed("test \"$(jq -r .current_baseline /var/lib/osmium-snapshot/root/.osmium/state.json)\" = legacy")
      vm.succeed("jq -e '.metadata.schema == \"osmium.filesystem.snapshot-metadata\"' /var/lib/osmium-snapshot/root/.osmium/snapshots/legacy.json")
      vm.succeed("curl --fail --user admin:test-admin-password http://127.0.0.1:3000/api/v1/repos/admin/migration")
      vm.succeed("test -e /etc/systemd/system/mythoclast-hello.service && systemctl is-active osmium-hello.service")
      vm.succeed("rm -f /var/lib/osmium-migration/.state-v1-complete; systemctl restart osmium-hello.service; test \"$(cat /var/lib/osmium-hello/state)\" = before-migration")
    '';
  };
in
assert !conflictingNamespaces;
{
  osmium-rebrand-fresh = fresh;
  osmium-rebrand-migration = migration;
}
