{ config, lib, pkgs, ... }:

let
  cfg = config.services.mythoclast.filesystemSnapshot;

  pathIsSafe = path:
    lib.hasPrefix "/" path
    && !(lib.any (part: part == "..") (lib.splitString "/" path))
    && !(lib.hasInfix "//" path)
    && path != "/";

  pathIsPersistent = path:
    (path == "/var/lib" || lib.hasPrefix "/var/lib/" path)
    || lib.any (root: path == root || lib.hasPrefix "${root}/" path)
      (lib.attrNames config.environment.persistence);

  relativePatternIsSafe = pattern:
    pattern != ""
    && !(lib.hasPrefix "/" pattern)
    && !(lib.hasInfix "//" pattern)
    && !(lib.any (part: part == "..") (lib.splitString "/" pattern));

  trackerAssertions = lib.concatLists (lib.mapAttrsToList
    (name: tracker: [
      {
        assertion = pathIsSafe tracker.source && pathIsPersistent tracker.source;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.source must be a safe persistent path under /var/lib or a declared persistence root.";
      }
      {
        assertion = pathIsSafe tracker.snapshotRoot && pathIsPersistent tracker.snapshotRoot;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.snapshotRoot must be a safe persistent path under /var/lib or a declared persistence root.";
      }
      {
        assertion = pathIsSafe tracker.stateDirectory && pathIsPersistent tracker.stateDirectory;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.stateDirectory must be a safe persistent path under /var/lib or a declared persistence root.";
      }
      {
        assertion = pathIsSafe tracker.reportDirectory && pathIsPersistent tracker.reportDirectory;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.reportDirectory must be a safe persistent path under /var/lib or a declared persistence root.";
      }
      {
        assertion = pathIsSafe tracker.cacheDirectory && pathIsPersistent tracker.cacheDirectory;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.cacheDirectory must be a safe persistent path under /var/lib or a declared persistence root.";
      }
      {
        assertion = tracker.source != tracker.snapshotRoot;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.source and snapshotRoot must differ.";
      }
      {
        assertion = tracker.retention.count != null || tracker.retention.age != null;
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.retention must specify count, age, or both.";
      }
      {
        assertion = tracker.schedule != "";
        message = "services.mythoclast.filesystemSnapshot.trackers.${name}.schedule must not be empty.";
      }
      {
        assertion = lib.all relativePatternIsSafe (tracker.exclusions ++ tracker.redactions);
        message = "services.mythoclast.filesystemSnapshot.trackers.${name} exclusions and redactions must be non-empty relative paths without escaping components.";
      }
      {
        assertion = tracker.administrative.user != "" && tracker.administrative.group != "";
        message = "services.mythoclast.filesystemSnapshot.trackers.${name} administrative user and group must not be empty.";
      }
    ])
    cfg.trackers);

  lifecycleScript = pkgs.writeShellScriptBin "mythoclast-filesystem-snapshot" ''
    exec ${pkgs.python3}/bin/python ${../../tools/filesystem_snapshot.py} "$@"
  '';

  trackerServices = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-baseline" {
      description = "Create the ${name} filesystem snapshot baseline";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = [ pkgs.btrfs-progs ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lifecycleScript}/bin/mythoclast-filesystem-snapshot baseline --source ${lib.escapeShellArg tracker.source} --snapshot-root ${lib.escapeShellArg tracker.snapshotRoot} --state-dir ${lib.escapeShellArg tracker.stateDirectory}";
      };
    })
    cfg.trackers;

  trackerObservationServices = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-observe" {
      description = "Capture the ${name} filesystem snapshot observation";
      path = [ pkgs.btrfs-progs ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lifecycleScript}/bin/mythoclast-filesystem-snapshot observe --source ${lib.escapeShellArg tracker.source} --snapshot-root ${lib.escapeShellArg tracker.snapshotRoot} --state-dir ${lib.escapeShellArg tracker.stateDirectory}";
      };
    })
    cfg.trackers;

  trackerObservationTimers = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-observe-timer" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = tracker.schedule;
        Persistent = true;
        Unit = "mythoclast-filesystem-snapshot-${name}-observe.service";
      };
    })
    cfg.trackers;

  trackerReportServices = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-report" {
      description = "Render the ${name} filesystem snapshot report";
      after = [ "mythoclast-filesystem-snapshot-${name}-observe.service" ];
      path = [ pkgs.btrfs-progs ];
      serviceConfig = {
        Type = "oneshot";
        User = tracker.administrative.user;
        Group = tracker.administrative.group;
        UMask = "0077";
        ExecStart = "${lifecycleScript}/bin/mythoclast-filesystem-snapshot report --source ${lib.escapeShellArg tracker.source} --snapshot-root ${lib.escapeShellArg tracker.snapshotRoot} --state-dir ${lib.escapeShellArg tracker.stateDirectory} --snapshot-id latest --threshold ${toString tracker.contentThreshold} ${lib.concatMapStringsSep " " (pattern: "--exclude ${lib.escapeShellArg pattern}") tracker.exclusions} ${lib.concatMapStringsSep " " (pattern: "--redact ${lib.escapeShellArg pattern}") tracker.redactions} --cache-dir ${lib.escapeShellArg tracker.cacheDirectory} --report-json ${lib.escapeShellArg "${tracker.reportDirectory}/latest.json"} --report-text ${lib.escapeShellArg "${tracker.reportDirectory}/latest.txt"} --mode ${tracker.administrative.mode}";
      };
    })
    cfg.trackers;

  trackerReportTimers = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-report-timer" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = tracker.reportSchedule;
        Persistent = true;
        Unit = "mythoclast-filesystem-snapshot-${name}-report.service";
      };
    })
    cfg.trackers;

  trackerRetentionServices = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-retain" {
      description = "Retain ${name} filesystem snapshots";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lifecycleScript}/bin/mythoclast-filesystem-snapshot retain --source ${lib.escapeShellArg tracker.source} --snapshot-root ${lib.escapeShellArg tracker.snapshotRoot} --state-dir ${lib.escapeShellArg tracker.stateDirectory} ${lib.optionalString (tracker.retention.count != null) "--count ${toString tracker.retention.count}"} ${lib.optionalString (tracker.retention.age != null) "--age ${toString tracker.retention.age}"}";
      };
    })
    cfg.trackers;

  trackerRetentionTimers = lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-retain-timer" {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = tracker.retentionSchedule; Persistent = true; Unit = "mythoclast-filesystem-snapshot-${name}-retain.service"; };
    })
    cfg.trackers;

  trackerPromotionServices = lib.filterAttrs (_: tracker: (tracker.promotionSnapshot or null) != null) (lib.mapAttrs'
    (name: tracker: lib.nameValuePair "mythoclast-filesystem-snapshot-${name}-promote" {
      description = "Promote an explicit ${name} filesystem snapshot";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lifecycleScript}/bin/mythoclast-filesystem-snapshot promote --source ${lib.escapeShellArg tracker.source} --snapshot-root ${lib.escapeShellArg tracker.snapshotRoot} --state-dir ${lib.escapeShellArg tracker.stateDirectory} --snapshot-id ${lib.escapeShellArg (tracker.promotionSnapshot or "")}";
      };
    })
     cfg.trackers);

  trackerDeploymentServices = lib.foldl' (services: name:
    let tracker = cfg.trackers.${name}; in
    if tracker.bundlePath == null then services else services // {
      "mythoclast-filesystem-snapshot-${name}-deploy" = {
        description = "Deploy the selected ${name} filesystem reconstruction bundle";
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          StandardInput = "file:${tracker.bundlePath}";
          ExecStart = "${lifecycleScript}/bin/mythoclast-filesystem-snapshot deploy --destination ${lib.escapeShellArg tracker.deploymentDestination} ${lib.optionalString (tracker.bundlePayloadDirectory != null) "--payload-dir ${lib.escapeShellArg tracker.bundlePayloadDirectory}"}";
        };
      };
    }) { } (lib.attrNames cfg.trackers);
in
{
  options.services.mythoclast.filesystemSnapshot = {
    enable = lib.mkEnableOption "filesystem snapshot drift tracking";

    trackers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
        options = {
          source = lib.mkOption {
            type = lib.types.str;
            description = "Persistent Btrfs source subvolume to track.";
          };

          snapshotRoot = lib.mkOption {
            type = lib.types.str;
            description = "Persistent root beneath which managed snapshots are stored.";
          };

          stateDirectory = lib.mkOption {
            type = lib.types.str;
            default = "${config.snapshotRoot}/.mythoclast";
            description = "Persistent directory containing snapshot metadata and tracker state.";
          };

          reportDirectory = lib.mkOption { type = lib.types.str; default = "${config.stateDirectory}/reports"; description = "Persistent directory for complete JSON and text reports."; };
          cacheDirectory = lib.mkOption { type = lib.types.str; default = "${config.stateDirectory}/cache"; description = "Persistent directory for validated immutable snapshot hash cache entries."; };
          reportSchedule = lib.mkOption { type = lib.types.str; default = config.schedule; description = "Systemd calendar expression for report generation."; };
          retentionSchedule = lib.mkOption { type = lib.types.str; default = "daily"; description = "Systemd calendar expression for retention."; };
           promotionSnapshot = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Explicit observation ID for the optional promotion oneshot."; };

           bundlePath = lib.mkOption {
             type = lib.types.nullOr lib.types.str;
             default = null;
             description = "Runtime path of a complete external reconstruction bundle to deploy; null disables deployment.";
           };

           deploymentDestination = lib.mkOption {
             type = lib.types.str;
             default = config.source;
             description = "Destination root beneath which the selected reconstruction bundle is deployed.";
           };

           bundlePayloadDirectory = lib.mkOption {
             type = lib.types.nullOr lib.types.str;
             default = null;
             description = "Optional runtime directory containing content-addressed payloads referenced by the bundle.";
           };

          schedule = lib.mkOption {
            type = lib.types.str;
            default = "daily";
            description = "Systemd calendar expression for scheduled observations.";
          };

          retention = {
            count = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = 10;
              description = "Maximum number of completed snapshots to retain.";
            };

            age = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = "Maximum age of completed snapshots in seconds.";
            };
          };

          contentThreshold = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1024 * 1024;
            description = "Maximum changed-file size for inline reconstruction content.";
          };

          exclusions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Relative path patterns excluded from traversal.";
          };

          redactions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Relative path patterns whose content payloads are redacted.";
          };

          administrative = {
            user = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "Administrative owner of reports and reconstruction artifacts.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "Administrative group of reports and reconstruction artifacts.";
            };

            mode = lib.mkOption {
              type = lib.types.strMatching "0[0-7]{3}";
              default = "0640";
              description = "Mode for administrative reports and reconstruction artifacts.";
            };
          };
        };
      }));
      default = { };
      description = "Btrfs subvolumes whose snapshots are managed for drift detection.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = trackerAssertions;
    systemd.services = trackerServices // trackerObservationServices // trackerReportServices // trackerRetentionServices // trackerPromotionServices // trackerDeploymentServices;
    systemd.timers = trackerObservationTimers // trackerReportTimers // trackerRetentionTimers;
    environment.persistence."/persistent".directories = lib.concatLists (lib.mapAttrsToList
      (_: tracker: [
        tracker.source
        tracker.snapshotRoot
        tracker.stateDirectory
        tracker.reportDirectory
        tracker.cacheDirectory
      ])
      cfg.trackers);
  };
}
