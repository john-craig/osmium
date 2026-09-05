{ config, lib, pkgs, ... }:

let
  giteaEnabled = config.services.osmium.gitea.enable;
  helloEnabled = config.services.osmium.hello.enable;
  snapshotCfg = config.services.osmium.filesystemSnapshot;
  snapshotEnabled = snapshotCfg.enable;

  snapshotMigrations = lib.concatStringsSep "\n" (lib.filter (value: value != "") (lib.mapAttrsToList
    (_: tracker: let
      oldState = lib.replaceStrings [ ".osmium" ] [ ".mythoclast" ] tracker.stateDirectory;
    in lib.optionalString (oldState != tracker.stateDirectory) ''
      if [ -e ${lib.escapeShellArg oldState} ] && [ ! -e ${lib.escapeShellArg tracker.stateDirectory} ]; then
         tmp=${lib.escapeShellArg "${tracker.stateDirectory}.osmium-migration.$$"}
         rm -rf "$tmp"
         cp -a ${lib.escapeShellArg oldState} "$tmp"
         mv "$tmp" ${lib.escapeShellArg tracker.stateDirectory}
      elif [ -e ${lib.escapeShellArg oldState} ] && [ -e ${lib.escapeShellArg tracker.stateDirectory} ]; then
        if [ -d ${lib.escapeShellArg tracker.stateDirectory} ] && [ -z "$(find ${lib.escapeShellArg tracker.stateDirectory} \( -type f -o -type l \) -print -quit)" ]; then
          cp -a ${lib.escapeShellArg oldState}/. ${lib.escapeShellArg tracker.stateDirectory}/
        else
          echo "Osmium migration conflict: both ${oldState} and ${tracker.stateDirectory} exist" >&2
          exit 1
        fi
      fi
     '') snapshotCfg.trackers));
  snapshotMetadataMigrations = lib.concatStringsSep "\n" (lib.mapAttrsToList (_: tracker: ''
    for state_file in ${lib.escapeShellArg "${tracker.stateDirectory}/snapshots"}/*.json; do
      [ -f "$state_file" ] || continue
      tmp="$state_file.migration.$$"
      ${pkgs.jq}/bin/jq 'if .metadata.schema == "mythoclast.filesystem.snapshot-metadata" then .metadata.schema = "osmium.filesystem.snapshot-metadata" else . end' "$state_file" > "$tmp"
      chmod --reference="$state_file" "$tmp"
      mv "$tmp" "$state_file"
    done
  '') snapshotCfg.trackers);
  snapshotUnitAliases = lib.mapAttrs'
    (name: _: lib.nameValuePair "osmium-filesystem-snapshot-${name}-baseline" {
      aliases = [ "mythoclast-filesystem-snapshot-${name}-baseline.service" ];
    }) snapshotCfg.trackers
    // lib.mapAttrs'
    (name: _: lib.nameValuePair "osmium-filesystem-snapshot-${name}-observe" {
      aliases = [ "mythoclast-filesystem-snapshot-${name}-observe.service" ];
    }) snapshotCfg.trackers
    // lib.mapAttrs'
    (name: _: lib.nameValuePair "osmium-filesystem-snapshot-${name}-report" {
      aliases = [ "mythoclast-filesystem-snapshot-${name}-report.service" ];
    }) snapshotCfg.trackers
    // lib.mapAttrs'
    (name: _: lib.nameValuePair "osmium-filesystem-snapshot-${name}-retain" {
      aliases = [ "mythoclast-filesystem-snapshot-${name}-retain.service" ];
    }) snapshotCfg.trackers
    // lib.mapAttrs'
    (name: tracker: lib.nameValuePair "osmium-filesystem-snapshot-${name}-promote" {
      aliases = lib.optional (tracker.promotionSnapshot != null) "mythoclast-filesystem-snapshot-${name}-promote.service";
    }) snapshotCfg.trackers
    // lib.mapAttrs'
    (name: tracker: lib.nameValuePair "osmium-filesystem-snapshot-${name}-deploy" {
      aliases = lib.optional (tracker.bundlePath != null) "mythoclast-filesystem-snapshot-${name}-deploy.service";
    }) snapshotCfg.trackers;
  legacyGiteaDriftCommand = pkgs.writeShellScriptBin "mythoclast-gitea-drift" ''
    exec osmium-gitea-drift "$@"
  '';
  legacyGiteaExportCommand = pkgs.writeShellScriptBin "mythoclast-gitea-export" ''
    exec osmium-gitea-export "$@"
  '';
  legacySnapshotCommand = pkgs.writeShellScriptBin "mythoclast-filesystem-snapshot" ''
    exec osmium-filesystem-snapshot "$@"
  '';
in
let
  migrationScript = pkgs.writeShellScript "osmium-legacy-state-migration" ''
    set -eu
    marker=/var/lib/osmium-migration/.state-v1-complete
    if [ -e "$marker" ]; then
      exit 0
    fi
    install -d -m 0750 /var/lib/osmium-migration
    if [ -d /var/lib/mythoclast-hello ] && [ ! -e /var/lib/osmium-hello ]; then
      tmp=/var/lib/.osmium-hello-migration.$$
      rm -rf "$tmp"
      cp -a /var/lib/mythoclast-hello "$tmp"
      mv "$tmp" /var/lib/osmium-hello
    elif [ -d /var/lib/mythoclast-hello ] && [ -e /var/lib/osmium-hello ]; then
      if [ -z "$(ls -A /var/lib/osmium-hello)" ]; then
        cp -a /var/lib/mythoclast-hello/. /var/lib/osmium-hello/
      else
        echo "Osmium migration conflict: both hello state directories exist" >&2
        exit 1
      fi
    fi
    if [ -d /var/lib/gitea ]; then
      for old in /var/lib/gitea/.mythoclast-*; do
        [ -e "$old" ] || continue
        new=$(printf '%s' "$old" | sed 's/\.mythoclast-/\.osmium-/')
        if [ -e "$new" ]; then
          echo "Osmium migration conflict: both $old and $new exist" >&2
          exit 1
        fi
        tmp="$new.migration.$$"
        rm -rf "$tmp"
        cp -a "$old" "$tmp"
        mv "$tmp" "$new"
      done
    fi
    ${lib.optionalString snapshotEnabled snapshotMigrations}
    ${lib.optionalString snapshotEnabled snapshotMetadataMigrations}
    if [ -d /var/lib/gitea ]; then
      for state_file in /var/lib/gitea/.osmium-*.json; do
        [ -f "$state_file" ] || continue
        tmp="$state_file.migration.$$"
        ${pkgs.jq}/bin/jq 'if .schema == "mythoclast.gitea.drift-report" then .schema = "osmium.gitea.drift-report" else . end' "$state_file" > "$tmp"
        chmod --reference="$state_file" "$tmp"
        mv "$tmp" "$state_file"
      done
    fi
    install -m 0640 /dev/null "$marker"
  '';
in
{
  imports = [
    (lib.mkAliasOptionModule [ "services" "mythoclast" ] [ "services" "osmium" ])
  ];

  config = {
    environment.systemPackages = lib.optionals giteaEnabled [ legacyGiteaDriftCommand legacyGiteaExportCommand ]
      ++ lib.optionals snapshotEnabled [ legacySnapshotCommand ];

    systemd.services = lib.mkMerge [
      {
        osmium-legacy-state-migration = {
          description = "Migrate legacy Mythoclast state to Osmium paths";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          before = [ "osmium-hello.service" "gitea.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = migrationScript;
          };
        };
        osmium-hello.aliases = lib.mkIf helloEnabled [ "mythoclast-hello.service" ];
        osmium-gitea-admin-bootstrap.aliases = lib.mkIf (giteaEnabled && config.services.osmium.gitea.admin.enable) [ "mythoclast-gitea-admin-bootstrap.service" ];
        osmium-gitea-admin-rotation.aliases = lib.mkIf (giteaEnabled && config.services.osmium.gitea.admin.rotation.enable) [ "mythoclast-gitea-admin-rotation.service" ];
        osmium-gitea-identities.aliases = lib.mkIf (giteaEnabled && (config.services.osmium.gitea.users != { } || config.services.osmium.gitea.organizations != { })) [ "mythoclast-gitea-identities.service" ];
        osmium-gitea-drift.aliases = lib.mkIf (giteaEnabled && config.services.osmium.gitea.driftDetection.enable && config.services.osmium.gitea.driftDetection.runAtStartup) [ "mythoclast-gitea-drift.service" ];
        osmium-gitea-drift-timer.aliases = lib.mkIf (giteaEnabled && config.services.osmium.gitea.driftDetection.enable && config.services.osmium.gitea.driftDetection.timer.enable) [ "mythoclast-gitea-drift-timer.service" ];
      }
      (lib.mkIf snapshotEnabled snapshotUnitAliases)
    ];

  };
}
