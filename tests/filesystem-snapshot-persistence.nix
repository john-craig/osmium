{ pkgs, module, microvm }:

pkgs.testers.runNixOSTest {
  name = "mythoclast-filesystem-snapshot-persistence";

  nodes.vm = {
    imports = [
      microvm.nixosModules.microvm
      module
    ];

    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    virtualisation.graphics = false;
    virtualisation.diskSize = 2048;
    environment.systemPackages = with pkgs; [ btrfs-progs jq util-linux ];

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

    services.mythoclast.filesystemSnapshot = {
      enable = true;
      trackers.test = {
        source = "/var/lib/mythoclast-btrfs/source";
        snapshotRoot = "/var/lib/mythoclast-btrfs/snapshots";
        stateDirectory = "/var/lib/mythoclast-btrfs/state";
        retention.count = 10;
      };
    };

    systemd.services.mythoclast-filesystem-snapshot-test-baseline.wantedBy = pkgs.lib.mkForce [ ];
  };

  testScript = ''
    def mount_snapshot_disk():
        vm.succeed("mkdir -p /persistent/snapshot-disk /var/lib/mythoclast-btrfs")
        vm.succeed("test -e /persistent/snapshot-disk/fs.img || (truncate -s 256M /persistent/snapshot-disk/fs.img && mkfs.btrfs -f /persistent/snapshot-disk/fs.img)")
        vm.succeed("mountpoint -q /var/lib/mythoclast-btrfs || mount -o loop /persistent/snapshot-disk/fs.img /var/lib/mythoclast-btrfs")

    def initialize_snapshot_tree():
        vm.succeed("btrfs subvolume show /var/lib/mythoclast-btrfs/source >/dev/null 2>&1 || btrfs subvolume create /var/lib/mythoclast-btrfs/source")
        vm.succeed("test -d /var/lib/mythoclast-btrfs/snapshots || mkdir /var/lib/mythoclast-btrfs/snapshots")
        vm.succeed("test -d /var/lib/mythoclast-btrfs/state || mkdir /var/lib/mythoclast-btrfs/state")

    vm.start(allow_reboot=True)
    mount_snapshot_disk()
    initialize_snapshot_tree()
    vm.succeed("printf baseline > /var/lib/mythoclast-btrfs/source/tracked")
    vm.succeed("systemctl start mythoclast-filesystem-snapshot-test-baseline.service")
    vm.succeed("systemctl start mythoclast-filesystem-snapshot-test-observe.service")
    vm.succeed("printf observed > /var/lib/mythoclast-btrfs/source/tracked")
    vm.succeed("systemctl start mythoclast-filesystem-snapshot-test-observe.service")
    baseline_id = vm.succeed("jq -r .current_baseline /var/lib/mythoclast-btrfs/state/state.json").strip()
    vm.succeed("test -d /var/lib/mythoclast-btrfs/snapshots && test $(find /var/lib/mythoclast-btrfs/state/snapshots -name '*.json' | wc -l) -eq 3")
    vm.succeed("jq -es 'all(.[]; .metadata.complete == true and .metadata.read_only == true and .complete == true)' /var/lib/mythoclast-btrfs/state/snapshots/*.json")
    vm.succeed("test $(jq -r .metadata.role /var/lib/mythoclast-btrfs/state/snapshots/" + baseline_id + ".json) = baseline")

    vm.shutdown()
    vm.start()
    mount_snapshot_disk()
    vm.succeed("test -f /var/lib/mythoclast-btrfs/source/tracked")
    vm.succeed("test \"$(cat /var/lib/mythoclast-btrfs/source/tracked)\" = observed")
    vm.succeed("test \"$(jq -r .current_baseline /var/lib/mythoclast-btrfs/state/state.json)\" = " + baseline_id)
    vm.succeed("test $(find /var/lib/mythoclast-btrfs/state/snapshots -name '*.json' | wc -l) -eq 3")
    vm.succeed("jq -es 'all(.[]; .metadata.complete == true and .metadata.read_only == true and .complete == true)' /var/lib/mythoclast-btrfs/state/snapshots/*.json")
    vm.succeed("systemctl start mythoclast-filesystem-snapshot-test-baseline.service")
    vm.succeed("test \"$(jq -r .current_baseline /var/lib/mythoclast-btrfs/state/state.json)\" = " + baseline_id)
  '';
}
