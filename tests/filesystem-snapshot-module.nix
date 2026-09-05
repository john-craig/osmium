{ pkgs, lib, module, persistenceModule ? { } }:

let
  base = {
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    boot.loader.grub.devices = [ "nodev" ];
  };

  evaluate = modules: (lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ persistenceModule base ] ++ modules;
  });

  valid = evaluate [
    module
    {
      system.stateVersion = "25.05";
      environment.persistence."/persistent" = { files = [ ]; };
      services.osmium.filesystemSnapshot = {
        enable = true;
        trackers.example = {
          source = "/persistent/data";
          snapshotRoot = "/var/lib/osmium-snapshots";
          schedule = "hourly";
          retention = { count = 5; age = 86400; };
          contentThreshold = 4096;
          exclusions = [ "cache" ];
          redactions = [ "secrets" ];
          administrative = { user = "root"; group = "wheel"; mode = "0600"; };
        };
      };
    }
  ];

  passes = configuration:
    let result = builtins.tryEval (evaluate [ module configuration ]); in
    result.success && lib.all (assertion: assertion.assertion) result.value.config.assertions;

  rejects = configuration:
    let result = builtins.tryEval (passes configuration); in
    !result.success || !result.value;
in
pkgs.runCommand "osmium-filesystem-snapshot-module-evaluation" { } ''
  test ${lib.boolToString (lib.all (assertion: assertion.assertion) valid.config.assertions)} = true
  test ${lib.boolToString (!(valid.config.systemd.services ? "osmium-filesystem-snapshot-example-deploy"))} = true
  ${let selected = evaluate [ module {
    system.stateVersion = "25.05";
    environment.persistence."/persistent" = { files = [ ]; };
    services.osmium.filesystemSnapshot = {
      enable = true;
      trackers.example = {
        source = "/persistent/data";
        snapshotRoot = "/var/lib/osmium-snapshots";
        bundlePath = "/run/osmium/reviewed-bundle.json";
      };
    };
  }]; in ''
    test ${lib.boolToString (selected.config.systemd.services ? "osmium-filesystem-snapshot-example-deploy")} = true
    test "${selected.config.systemd.services."osmium-filesystem-snapshot-example-deploy".serviceConfig.StandardInput}" = "file:/run/osmium/reviewed-bundle.json"
  ''}
  ${lib.optionalString (!rejects {
    system.stateVersion = "25.05";
    services.osmium.filesystemSnapshot = {
      enable = true;
      trackers.example = {
        source = "/etc/data";
        snapshotRoot = "/var/lib/snapshots";
      };
    };
  }) ''exit 1''}
  ${lib.optionalString (!rejects {
    system.stateVersion = "25.05";
    services.osmium.filesystemSnapshot = {
      enable = true;
      trackers.example = {
        source = "/var/lib/data";
        snapshotRoot = "/var/lib/data";
      };
    };
  }) ''exit 1''}
  ${lib.optionalString (!rejects {
    system.stateVersion = "25.05";
    services.osmium.filesystemSnapshot = {
      enable = true;
      trackers.example = {
        source = "/var/lib/data";
        snapshotRoot = "/var/lib/snapshots";
        exclusions = [ "../secrets" ];
      };
    };
  }) ''exit 1''}
  touch $out
''
