{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.opencodeServer;
  stateDir = "${cfg.home}/.local/share/opencode";
  authFile = "${stateDir}/auth.json";
  reconciliationDir = "${cfg.home}/.local/share/osmium-opencode";
  providerRecord = "${reconciliationDir}/provider-auth.json";
  serverRecord = "${reconciliationDir}/server-environment.json";
  serverEnvironmentFile = "${cfg.credentials.guestDirectory}/${cfg.credentials.serverEnvironmentFile}";
  providerAuthFile = "${cfg.credentials.guestDirectory}/${cfg.credentials.providerAuthFile}";
  microvmConfig = lib.optionalAttrs (options ? microvm) {
    microvm = {
      shares = [ {
        proto = "virtiofs";
        cache = "never";
        tag = "osmium-opencode-credentials";
        source = cfg.credentials.hostDirectory;
        mountPoint = cfg.credentials.guestDirectory;
        readOnly = true;
      } ] ++ lib.mapAttrsToList (name: workspace: {
        proto = workspace.proto;
        cache = if workspace.proto == "virtiofs" then "never" else "auto";
        tag = "osmium-opencode-workspace-${name}";
        source = workspace.hostPath;
        mountPoint = workspace.guestPath;
        readOnly = true;
      }) cfg.workspaces;
      forwardPorts = [ { from = "host"; proto = "tcp"; host.port = cfg.hostPort; guest.port = cfg.guestPort; } ];
    };
  };
  names = lib.attrNames cfg.workspaces;
  workspacePaths = lib.mapAttrsToList (_: workspace: workspace.guestPath) cfg.workspaces;
  allMountPaths = [ cfg.credentials.guestDirectory ] ++ workspacePaths;
  overlaps = left: right: left == right || lib.hasPrefix "${left}/" right || lib.hasPrefix "${right}/" left;
  mountOverlaps = lib.concatMap (left: lib.filter (right: left != right && overlaps left right) allMountPaths) allMountPaths;
  safeRelative = value: builtins.match "^[A-Za-z0-9._-]+$" value != null;
  json = pkgs.formats.json { };
  xdgOpen = pkgs.writeShellScriptBin "xdg-open" "exit 0";
  declaration = builtins.toJSON {
    listenAddress = cfg.listenAddress;
    guestPort = cfg.guestPort;
    hostPort = cfg.hostPort;
    httpUsername = cfg.httpUsername;
    corsOrigins = cfg.corsOrigins;
    workingDirectory = cfg.workingDirectory;
    settings = cfg.settings;
    tui = cfg.tui;
    extraPackages = map (package: lib.getName package) cfg.extraPackages;
    credentials = {
      guestDirectory = cfg.credentials.guestDirectory;
      serverEnvironmentFile = cfg.credentials.serverEnvironmentFile;
      providerAuthFile = cfg.credentials.providerAuthFile;
    };
    workspaces = lib.mapAttrs (_: workspace: {
      guestPath = workspace.guestPath;
      readOnly = workspace.readOnly;
      proto = workspace.proto;
    }) cfg.workspaces;
    persistence = cfg.persistence.enable;
  };
  reconcile = pkgs.writeShellScript "osmium-opencode-reconcile" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.jq pkgs.systemd pkgs.util-linux ]}
    cred=${lib.escapeShellArg cfg.credentials.guestDirectory}
    env_file=${lib.escapeShellArg serverEnvironmentFile}
    provider=${lib.escapeShellArg providerAuthFile}
    auth=${lib.escapeShellArg authFile}
    records=${lib.escapeShellArg reconciliationDir}
    provider_record=${lib.escapeShellArg providerRecord}
    server_record=${lib.escapeShellArg serverRecord}
    user=${lib.escapeShellArg cfg.user}
    group=${lib.escapeShellArg cfg.group}
    fail_closed() {
      timeout 2s systemctl --user -M "$user@" stop opencode-web.service 2>/dev/null || true
      echo "$1" >&2
      exit 1
    }
    install -d -m 0750 -o "$user" -g "$group" "$records" "$(dirname "$auth")"
    [ -d "$cred" ] || fail_closed "OpenCode credential mount is unavailable"
    [ -r "$env_file" ] && [ -s "$env_file" ] || fail_closed "OpenCode server environment file is unavailable"
    password=$(awk -F= '$1 == "OPENCODE_SERVER_PASSWORD" { print substr($0, index($0, "=") + 1); exit }' "$env_file")
    [ -n "$password" ] || fail_closed "OpenCode server environment file has no password"
    username=$(awk -F= '$1 == "OPENCODE_SERVER_USERNAME" { print substr($0, index($0, "=") + 1); exit }' "$env_file")
    [ "$username" = ${lib.escapeShellArg cfg.httpUsername} ] || fail_closed "OpenCode server environment file username does not match declaration"
    [ -r "$provider" ] && [ -s "$provider" ] || fail_closed "OpenCode provider auth file is unavailable"
    jq -e 'type == "object" and length > 0 and all(.[];
      type == "object" and
      ((.type == "api" and (.key | type == "string") and (.key | length > 0)) or
       (.type == "oauth" and (.access | type == "string") and (.access | length > 0) and
        (.refresh | type == "string") and (.refresh | length > 0) and (.expires | type == "number")) or
       (.type == "wellknown" and (.key | type == "string") and (.key | length > 0) and
        (.token | type == "string") and (.token | length > 0))))' "$provider" >/dev/null || fail_closed "OpenCode provider auth has no valid provider credentials"
    env_digest=$(sha256sum "$env_file" | cut -d ' ' -f 1)
    provider_digest=$(sha256sum "$provider" | cut -d ' ' -f 1)
    old_provider=$(jq -r '.digest // empty' "$provider_record" 2>/dev/null || true)
    if [ "$provider_digest" != "$old_provider" ]; then
      tmp=$(mktemp "$(dirname "$auth")/.auth.XXXXXX")
      install -o "$user" -g "$group" -m 0600 "$provider" "$tmp"
      mv -f "$tmp" "$auth"
      tmp_record=$(mktemp "$provider_record.XXXXXX")
      jq -cn --arg digest "$provider_digest" '{schema_version:1,digest:$digest,status:"applied"}' > "$tmp_record"
      chown "$user:$group" "$tmp_record"; chmod 0640 "$tmp_record"; mv -f "$tmp_record" "$provider_record"
      timeout 2s systemctl --user -M "$user@" --no-block try-restart opencode-web.service || true
    fi
    old_env=$(jq -r '.digest // empty' "$server_record" 2>/dev/null || true)
    if [ "$env_digest" != "$old_env" ]; then
      tmp_record=$(mktemp "$server_record.XXXXXX")
      jq -cn --arg digest "$env_digest" '{schema_version:1,digest:$digest,status:"applied"}' > "$tmp_record"
      chown "$user:$group" "$tmp_record"; chmod 0640 "$tmp_record"; mv -f "$tmp_record" "$server_record"
      timeout 2s systemctl --user -M "$user@" --no-block try-restart opencode-web.service || true
    fi
  '';
  observe = pkgs.writeShellScriptBin "osmium-opencode-observe" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.systemd ]}
    runtime_port=${toString cfg.guestPort}
    observed_port=$(systemctl --user -M ${lib.escapeShellArg cfg.user}@ show-environment 2>/dev/null | awk -F= '$1 == "OSMIUM_OPENCODE_RUNTIME_PORT" { print $2; exit }' || true)
    case "$observed_port" in
      *[!0-9]*) ;;
      [0-9]*) runtime_port="$observed_port" ;;
    esac
    ${pkgs.jq}/bin/jq -cn \
      --arg user ${lib.escapeShellArg cfg.user} \
      --arg home ${lib.escapeShellArg cfg.home} \
      --arg address ${lib.escapeShellArg cfg.listenAddress} \
      --argjson guestPort "$runtime_port" \
      --arg username ${lib.escapeShellArg cfg.httpUsername} \
      --arg workingDirectory ${lib.escapeShellArg cfg.workingDirectory} \
      --argjson workspaces ${lib.escapeShellArg (builtins.toJSON (map (name: { inherit name; guestPath = cfg.workspaces.${name}.guestPath; readOnly = cfg.workspaces.${name}.readOnly; proto = cfg.workspaces.${name}.proto; hostPath = { unresolved = true; reason = "host-source-not-observable"; }; }) names))} \
      '{schema_version:1,source:{origin:"observed",scope:"guest-runtime"},complete:false,activation_ready:false,provenance:{user:$user,home:$home},server:{listen_address:$address,guest_port:$guestPort,http_username:$username,working_directory:$workingDirectory},workspaces:$workspaces,credentials:{host_directory:{unresolved:true,reason:"host-source-not-observable"},secrets:{excluded:true}},findings:[{code:"host-only-input",field:"credentials.hostDirectory"},{code:"secret-excluded",field:"credentials"}]}'
  '';
  capture = pkgs.writeShellScriptBin "osmium-opencode-capture" ''
    exec ${observe}/bin/osmium-opencode-observe "$@"
  '';
  readiness = pkgs.writeShellScript "osmium-opencode-readiness" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.curl pkgs.systemd ]}
    env_file=${lib.escapeShellArg serverEnvironmentFile}
    password=$(awk -F= '$1 == "OPENCODE_SERVER_PASSWORD" { print substr($0, index($0, "=") + 1); exit }' "$env_file")
    [ -n "$password" ]
    systemctl --user -M ${lib.escapeShellArg cfg.user}@ --no-block start opencode-web.service
    for attempt in $(seq 1 60); do
      if curl --fail --silent --connect-timeout 1 --max-time 5 --user "${cfg.httpUsername}:$password" "http://127.0.0.1:${toString cfg.guestPort}/global/health"; then
        exit 0
      fi
      sleep 1
    done
    exit 1
  '';
  drift = pkgs.writeShellScriptBin "osmium-opencode-drift" ''
    set -eu
    observed=$(${observe}/bin/osmium-opencode-observe)
    ${pkgs.jq}/bin/jq --argjson declared ${lib.escapeShellArg declaration} \
      '. + {declared:$declared,drift:(.server.guest_port != $declared.guestPort or .server.listen_address != $declared.listenAddress),candidate:{services:{osmium:{opencodeServer:(.server.guest_port as $port | .server.listen_address as $address | $declared | .guestPort = $port | .listenAddress = $address)}},provenance:{origin:"runtime-observation",review_only:true},complete:false,activation_ready:false,findings:[{code:"host-only-input",field:"credentials.hostDirectory"}]}}' <<< "$observed"
  '';
in
{
  options.services.osmium.opencodeServer = {
    enable = lib.mkEnableOption "the Osmium OpenCode server";
    package = lib.mkPackageOption pkgs "opencode" { };
    user = lib.mkOption { type = lib.types.strMatching "[a-z_][a-z0-9_-]*"; default = "opencode"; description = "Service account."; };
    group = lib.mkOption { type = lib.types.strMatching "[a-z_][a-z0-9_-]*"; default = "opencode"; description = "Service group."; };
    uid = lib.mkOption { type = lib.types.ints.between 1000 60000; default = 1984; description = "Stable service UID."; };
    home = lib.mkOption { type = lib.types.str; default = "/var/lib/opencode"; description = "Private OpenCode home."; };
    homeStateVersion = lib.mkOption { type = lib.types.str; default = "25.05"; description = "Home Manager state version."; };
    listenAddress = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "Guest listen address."; };
    guestPort = lib.mkOption { type = lib.types.port; default = 4096; description = "Guest TCP port."; };
    hostPort = lib.mkOption { type = lib.types.port; default = 4096; description = "Forwarded host TCP port."; };
    httpUsername = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "opencode"; description = "HTTP Basic Auth username."; };
    corsOrigins = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Allowed browser origins."; };
    workingDirectory = lib.mkOption { type = lib.types.str; default = "/var/lib/opencode/workspace"; description = "OpenCode working directory."; };
    settings = lib.mkOption { type = json.type; default = { }; description = "OpenCode JSON settings."; };
    tui = lib.mkOption { type = json.type; default = { }; description = "OpenCode TUI settings."; };
    extraPackages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; description = "Additional packages on OpenCode's PATH."; };
    credentials = {
      hostDirectory = lib.mkOption { type = lib.types.str; default = "/run/secrets/opencode"; description = "Host credential directory."; };
      guestDirectory = lib.mkOption { type = lib.types.str; default = "/run/opencode/credentials"; description = "Guest credential mount."; };
      serverEnvironmentFile = lib.mkOption { type = lib.types.str; default = "server.env"; description = "Environment filename below the credential mount."; };
      providerAuthFile = lib.mkOption { type = lib.types.str; default = "auth.json"; description = "Provider auth filename below the credential mount."; };
    };
    workspaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          hostPath = lib.mkOption { type = lib.types.str; description = "Host workspace path."; };
          guestPath = lib.mkOption { type = lib.types.str; description = "Absolute guest workspace path."; };
          readOnly = lib.mkOption { type = lib.types.bool; default = true; description = "Mount read-only."; };
          proto = lib.mkOption { type = lib.types.enum [ "9p" "virtiofs" ]; default = "virtiofs"; description = "MicroVM share protocol."; };
        };
      }));
      default = { };
      description = "Independent OpenCode workspace shares.";
    };
    persistence.enable = lib.mkEnableOption "OpenCode persistence" // { default = true; };
    reverseConfiguration.enable = lib.mkEnableOption "OpenCode reverse configuration tooling";
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = lib.hasPrefix "/" cfg.home && lib.hasPrefix "/" cfg.credentials.guestDirectory; message = "OpenCode home and credential guestDirectory must be absolute paths."; }
      { assertion = safeRelative cfg.credentials.serverEnvironmentFile && safeRelative cfg.credentials.providerAuthFile; message = "OpenCode credential filenames must be simple relative filenames."; }
      { assertion = cfg.listenAddress == "127.0.0.1" || cfg.listenAddress == "::1" || cfg.listenAddress == "localhost" || cfg.credentials.serverEnvironmentFile != ""; message = "Non-loopback OpenCode listeners require server authentication."; }
      { assertion = mountOverlaps == [ ]; message = "OpenCode mount paths must be unique and non-overlapping."; }
      { assertion = lib.all (path: lib.hasPrefix "/" path) workspacePaths; message = "OpenCode workspace paths must be absolute."; }
      { assertion = lib.length (lib.unique (map (forward: forward.host.port) config.microvm.forwardPorts)) == lib.length config.microvm.forwardPorts; message = "OpenCode host port collides with another MicroVM forwarding rule."; }
    ];
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = { uid = cfg.uid; group = cfg.group; home = cfg.home; createHome = true; isNormalUser = true; hashedPassword = "!"; linger = true; };
    systemd.tmpfiles.rules = [
      "d /nix/var/nix/profiles/per-user 0755 root root -"
      "d /nix/var/nix/profiles/per-user/${cfg.user} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.workingDirectory} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.home}/.local 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.home}/.local/state 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.home}/.config 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.home}/.cache 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.home}/.local/share 0750 ${cfg.user} ${cfg.group} -"
      "d ${stateDir} 0750 ${cfg.user} ${cfg.group} -"
    ];
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
      home-manager.users.${cfg.user} = {
      home.stateVersion = cfg.homeStateVersion;
      home.homeDirectory = cfg.home;
      home.packages = [ xdgOpen ];
      programs.opencode = {
        enable = true;
        package = cfg.package;
        settings = cfg.settings;
        tui = cfg.tui;
        extraPackages = cfg.extraPackages ++ [ xdgOpen ];
        web = {
          enable = true;
          environmentFile = serverEnvironmentFile;
          extraArgs = [ "--hostname" cfg.listenAddress "--port" (toString cfg.guestPort) ] ++ lib.concatMap (origin: [ "--cors" origin ]) cfg.corsOrigins;
        };
      };
      systemd.user.services.opencode-web = {
        Unit = {
          After = [ "default.target" ];
          Wants = [ "default.target" ];
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
    nix.daemon.enable = true;
    nix.settings.allowed-users = [ "root" cfg.user ];
    systemd.sockets.nix-daemon.wantedBy = [ "sockets.target" ];
    systemd.services."home-manager-${cfg.user}" = {
      after = [ "nix-daemon.socket" ];
      requires = [ "nix-daemon.socket" ];
      wantedBy = [ "multi-user.target" ];
      environment.NIX_REMOTE = "daemon";
    };
    systemd.services.osmium-opencode-reconcile = {
      description = "Validate and reconcile OpenCode runtime credentials";
      wantedBy = [ "multi-user.target" ];
      before = [ "user@${toString cfg.uid}.service" ];
      path = [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.jq pkgs.systemd pkgs.util-linux ];
      serviceConfig = { Type = "oneshot"; ExecStart = reconcile; User = "root"; };
    };
    systemd.services.linger-users = {
      after = [ "osmium-opencode-reconcile.service" ];
      requires = [ "osmium-opencode-reconcile.service" ];
    };
    systemd.paths.osmium-opencode-reconcile = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = { PathChanged = serverEnvironmentFile; PathModified = providerAuthFile; Unit = "osmium-opencode-reconcile.service"; };
    };
    systemd.timers.osmium-opencode-reconcile = { wantedBy = [ "timers.target" ]; timerConfig = { OnBootSec = "10s"; OnUnitActiveSec = "60s"; Unit = "osmium-opencode-reconcile.service"; }; };
    systemd.services.osmium-opencode-ready = {
      wantedBy = [ "multi-user.target" ];
      after = [ "osmium-opencode-reconcile.service" "home-manager-${cfg.user}.service" "user@${toString cfg.uid}.service" ];
      requires = [ "osmium-opencode-reconcile.service" "home-manager-${cfg.user}.service" "user@${toString cfg.uid}.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = readiness; };
    };
    environment.systemPackages = [ xdgOpen ]
      ++ lib.optional cfg.reverseConfiguration.enable observe
      ++ lib.optional cfg.reverseConfiguration.enable capture
      ++ lib.optional cfg.reverseConfiguration.enable drift;
    environment.persistence."/persistent" = lib.mkIf cfg.persistence.enable {
      directories = [
        { directory = stateDir; user = cfg.user; group = cfg.group; mode = "0750"; }
        { directory = reconciliationDir; user = cfg.user; group = cfg.group; mode = "0750"; }
      ];
    };
  } // microvmConfig // {
    networking.firewall.allowedTCPPorts = [ cfg.guestPort ];
  });
}
