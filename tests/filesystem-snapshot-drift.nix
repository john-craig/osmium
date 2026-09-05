{ pkgs, microvm, module }:

let
  snapshotTool = "${pkgs.python3}/bin/python ${../tools/filesystem_snapshot.py}";

  node = {
    imports = [
      microvm.nixosModules.microvm
      module
    ];

    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    virtualisation.graphics = false;
    virtualisation.diskSize = 4096;
    environment.systemPackages = with pkgs; [ btrfs-progs jq util-linux coreutils ];

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

    services.osmium.filesystemSnapshot = {
      enable = true;
      trackers.test = {
        source = "/var/lib/osmium-btrfs/source";
        snapshotRoot = "/var/lib/osmium-btrfs/snapshots";
        stateDirectory = "/var/lib/osmium-btrfs/state";
        reportDirectory = "/var/lib/osmium-btrfs/reports";
        cacheDirectory = "/var/lib/osmium-btrfs/cache";
        contentThreshold = 16;
        exclusions = [ ];
        redactions = [ "secret" ];
        retention.count = 3;
        bundlePath = "/run/osmium/reviewed-bundle.json";
        deploymentDestination = "/var/lib/osmium-btrfs/source";
      };
    };

    systemd.services.osmium-filesystem-snapshot-test-baseline.wantedBy = pkgs.lib.mkForce [ ];
    systemd.services.osmium-filesystem-snapshot-test-deploy.wantedBy = pkgs.lib.mkForce [ ];
  };
in
pkgs.testers.runNixOSTest {
  name = "osmium-filesystem-snapshot-drift";
  nodes = {
    vm1 = node;
    vm2 = node;
  };

  testScript = ''
    def mount_snapshot_disk(machine):
        machine.succeed("mkdir -p /persistent/snapshot-disk /var/lib/osmium-btrfs")
        machine.succeed("test -e /persistent/snapshot-disk/fs.img || (truncate -s 512M /persistent/snapshot-disk/fs.img && mkfs.btrfs -f /persistent/snapshot-disk/fs.img)")
        machine.succeed("mountpoint -q /var/lib/osmium-btrfs || mount -o loop /persistent/snapshot-disk/fs.img /var/lib/osmium-btrfs")

    def initialize_tree(machine):
        machine.succeed("btrfs subvolume show /var/lib/osmium-btrfs/source >/dev/null 2>&1 || btrfs subvolume create /var/lib/osmium-btrfs/source")
        machine.succeed("mkdir -p /var/lib/osmium-btrfs/snapshots /var/lib/osmium-btrfs/state /var/lib/osmium-btrfs/reports /var/lib/osmium-btrfs/cache")
        machine.succeed("printf baseline > /var/lib/osmium-btrfs/source/tracked")
        machine.succeed("printf '%s' 'aaaaaaaaaaaaaaaaaaaaaaaa' > /var/lib/osmium-btrfs/source/large")
        machine.succeed("printf old-secret > /var/lib/osmium-btrfs/source/secret")
        machine.succeed("chmod 0644 /var/lib/osmium-btrfs/source/tracked /var/lib/osmium-btrfs/source/large /var/lib/osmium-btrfs/source/secret")
        machine.succeed("touch -m -d @1000000000 /var/lib/osmium-btrfs/source/tracked /var/lib/osmium-btrfs/source/large /var/lib/osmium-btrfs/source/secret")

    def start_report(machine):
        machine.succeed("systemctl reset-failed osmium-filesystem-snapshot-test-report.service; set +e; systemctl start osmium-filesystem-snapshot-test-report.service; status=$?; set -e; test $status -eq 1")

    vm1.start()
    vm1.wait_for_unit("multi-user.target")
    mount_snapshot_disk(vm1)
    initialize_tree(vm1)
    vm1.succeed("systemctl start osmium-filesystem-snapshot-test-baseline.service")
    vm1.succeed("jq -e '(.metadata.read_only == true) and (.metadata.complete == true) and (.complete == true)' /var/lib/osmium-btrfs/state/snapshots/*.json")
    baseline_id = vm1.succeed("jq -r .current_baseline /var/lib/osmium-btrfs/state/state.json").strip()
    baseline_path = "/var/lib/osmium-btrfs/state/snapshots/" + baseline_id + ".json"
    vm1.succeed("test \"$(jq -r .metadata.role " + baseline_path + ")\" = baseline")

    # This is an external mutation: no Osmium operation touches the source.
    vm1.succeed("printf observed > /var/lib/osmium-btrfs/source/tracked && chmod 0600 /var/lib/osmium-btrfs/source/tracked && touch -m -d @1000000001 /var/lib/osmium-btrfs/source/tracked")
    vm1.succeed("systemctl start osmium-filesystem-snapshot-test-observe.service")
    start_report(vm1)
    vm1.succeed("jq -e 'any(.changes[]; .classification == \"content-modified\" and (.reasons | index(\"content\")) and has(\"content\"))' /var/lib/osmium-btrfs/reports/latest.json")
    vm1.succeed("jq -e 'any(.changes[]; .classification == \"content-modified\" and (.reasons | index(\"mode\")))' /var/lib/osmium-btrfs/reports/latest.json")
    vm1.succeed("jq -se 'all(.[]; .metadata.read_only == true and .metadata.complete == true and .complete == true)' /var/lib/osmium-btrfs/state/snapshots/*.json")
    observed_manifest = vm1.succeed("jq -c .metadata.observed_manifest /var/lib/osmium-btrfs/reports/latest.json").strip()

    # The host test driver is the artifact bridge. The bytes below came from VM1.
    bundle_b64 = vm1.succeed("${snapshotTool} export drift-report /var/lib/osmium-btrfs/reports/latest.json | base64 -w0").strip()
    vm1.succeed("printf '%s' " + bundle_b64 + " | base64 -d > /run/exported-bundle.json")
    vm1.succeed("${snapshotTool} validate reconstruction-bundle /run/exported-bundle.json")
    vm1.succeed("jq -e '.complete == true and (.incomplete | length) == 0' /run/exported-bundle.json")

    # Oversized and redacted content is classified but cannot be exported as complete.
    vm1.succeed("printf '%s' 'bbbbbbbbbbbbbbbbbbbbbbbb' > /var/lib/osmium-btrfs/source/large && printf new-secret > /var/lib/osmium-btrfs/source/secret")
    vm1.succeed("systemctl start osmium-filesystem-snapshot-test-observe.service")
    start_report(vm1)
    vm1.succeed("jq -e 'any(.changes[]; .path == \"bGFyZ2U\" and (.reasons | index(\"content-diff-omitted\"))) and any(.changes[]; .path == \"c2VjcmV0\" and (.reasons | index(\"content-redacted\")))' /var/lib/osmium-btrfs/reports/latest.json")
    vm1.succeed("set +e; ${snapshotTool} export drift-report /var/lib/osmium-btrfs/reports/latest.json > /run/incomplete.json; status=$?; set -e; test $status -eq 20")

    # Every unsafe bundle is rejected before its destination sentinel changes.
    vm1.succeed("printf sentinel > /run/deploy-sentinel")
    vm1.succeed("jq '.operations[0].path = \"Li4vZXNjYXBl\"' /run/exported-bundle.json > /run/escape.json")
    vm1.fail("${snapshotTool} deploy reconstruction-bundle /run/escape.json --destination /var/lib/osmium-btrfs/source")
    vm1.succeed("test \"$(cat /run/deploy-sentinel)\" = sentinel")
    vm1.succeed("jq '(.payloads | keys[0]) as $key | .payloads[$key] = \"aW52YWxpZA\"' /run/exported-bundle.json > /run/bad-payload.json")
    vm1.fail("${snapshotTool} deploy reconstruction-bundle /run/bad-payload.json --destination /var/lib/osmium-btrfs/source")

    # A lineage edit makes report an operational failure, not deletion drift.
    vm1.succeed("cp " + baseline_path + " /run/baseline-record.json && jq '.metadata.source_id = \"wrong-lineage\"' " + baseline_path + " > /run/changed-record.json && cp /run/changed-record.json " + baseline_path)
    vm1.fail("${snapshotTool} report --source /var/lib/osmium-btrfs/source --snapshot-root /var/lib/osmium-btrfs/snapshots --state-dir /var/lib/osmium-btrfs/state --snapshot-id latest")
    vm1.succeed("cp /run/baseline-record.json " + baseline_path)

    # An incomplete record simulates an interrupted comparison and is never accepted.
    observation_id = vm1.succeed("jq -r '.observation_snapshot' /var/lib/osmium-btrfs/reports/latest.json").strip()
    observation_path = "/var/lib/osmium-btrfs/state/snapshots/" + observation_id + ".json"
    vm1.succeed("cp " + observation_path + " /run/observation-record.json && jq '.complete = false | .metadata.complete = false' " + observation_path + " > /run/interrupted.json && cp /run/interrupted.json " + observation_path)
    vm1.fail("${snapshotTool} report --source /var/lib/osmium-btrfs/source --snapshot-root /var/lib/osmium-btrfs/snapshots --state-dir /var/lib/osmium-btrfs/state --snapshot-id " + observation_id)
    vm1.succeed("cp /run/observation-record.json " + observation_path)

    # Retention keeps the baseline and active references while deleting eligible history.
    vm1.succeed("systemctl start osmium-filesystem-snapshot-test-observe.service")
    vm1.succeed("jq --arg id " + observation_id + " '.active_references = [$id]' /var/lib/osmium-btrfs/state/state.json > /run/state.json && cp /run/state.json /var/lib/osmium-btrfs/state/state.json")
    vm1.succeed("${snapshotTool} retain --source /var/lib/osmium-btrfs/source --snapshot-root /var/lib/osmium-btrfs/snapshots --state-dir /var/lib/osmium-btrfs/state --count 2")
    vm1.succeed("test -f " + baseline_path)

    # A writable managed snapshot is unsafe and cannot be compared.
    vm1.succeed("btrfs property set -ts \"$(jq -r .path " + baseline_path + ")\" ro false")
    vm1.fail("${snapshotTool} report --source /var/lib/osmium-btrfs/source --snapshot-root /var/lib/osmium-btrfs/snapshots --state-dir /var/lib/osmium-btrfs/state --snapshot-id " + observation_id)
    vm1.succeed("btrfs property set -ts \"$(jq -r .path " + baseline_path + ")\" ro true")
    vm1.shutdown()

    vm2.start()
    vm2.wait_for_unit("multi-user.target")
    mount_snapshot_disk(vm2)
    initialize_tree(vm2)
    vm2.succeed("systemctl start osmium-filesystem-snapshot-test-baseline.service")
    vm2.succeed("mkdir -p /run/osmium")
    vm2.succeed("printf '%s' " + bundle_b64 + " | base64 -d > /run/osmium/reviewed-bundle.json")
    vm2.succeed("systemctl start osmium-filesystem-snapshot-test-deploy.service")
    vm2.succeed("test \"$(cat /var/lib/osmium-btrfs/source/tracked)\" = observed")
    vm2.succeed("test \"$(stat -c %a /var/lib/osmium-btrfs/source/tracked)\" = 600")
    recreated_manifest = vm2.succeed("${pkgs.python3}/bin/python -c 'import sys; sys.path.insert(0, \"${../tools}\"); from filesystem_snapshot import canonical_tree, canonical_json; print(canonical_json(canonical_tree(\"/var/lib/osmium-btrfs/source\")).decode(), end=\"\")'").strip()
    assert recreated_manifest == observed_manifest
  '';
}
