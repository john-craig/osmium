{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.fdroidRepository;
  artifacts = lib.attrValues cfg.artifacts;
  artifactLedger = builtins.toJSON (lib.mapAttrsToList (_: artifact: {
    package = artifact.packageName;
    version_code = artifact.versionCode;
    version_name = artifact.versionName;
    sha256 = artifact.sha256;
    path = "/var/lib/fdroid-repository/repo/${artifact.packageName}_${toString artifact.versionCode}.apk";
    file = "${artifact.packageName}_${toString artifact.versionCode}.apk";
  }) cfg.artifacts);
  repositoryLedger = builtins.toJSON {
    repository_id = cfg.repositoryId;
    name = cfg.name;
    description = cfg.description;
    base_url = cfg.baseUrl;
    guest_port = cfg.guestPort;
    host_port = cfg.hostPort;
    signing = {
      keystore_file = cfg.signing.keystoreFile;
      password_file = cfg.signing.passwordFile;
      key_alias = cfg.signing.keyAlias;
    };
    artifacts = builtins.fromJSON artifactLedger;
  };
  stateDir = cfg.stateDir;
  repoDir = "${stateDir}/repo";
  readyMarker = "${stateDir}/.ready";
  generationLedger = "${stateDir}/ledger.json";
  tool = pkgs.writeShellScriptBin "osmium-fdroid-repository" ''
    exec ${pkgs.python3}/bin/python ${../../tools/fdroid_repository.py} --state-dir ${lib.escapeShellArg stateDir} "$@"
  '';
  generation = pkgs.writeShellScript "osmium-fdroid-repository-generate" ''
    set -eu
    state=${lib.escapeShellArg stateDir}
    repo=$state/repo
    temporary=$(mktemp -d "$state/.generation.XXXXXX")
    trap 'rm -rf "$temporary"' EXIT
    install -d -m 0750 "$temporary/repo" "$temporary/metadata"
    ${lib.concatMapStringsSep "\n" (artifact: ''
      source=${lib.escapeShellArg (toString artifact.path)}
      destination="$temporary/repo/${artifact.packageName}_${toString artifact.versionCode}.apk"
      [ -r "$source" ] || { echo "F-Droid artifact is unreadable: ${artifact.packageName}" >&2; exit 1; }
      ${lib.optionalString (artifact.sha256 != null) ''
        actual=$(sha256sum "$source" | cut -d ' ' -f 1)
        [ "$actual" = ${lib.escapeShellArg artifact.sha256} ] || { echo "F-Droid artifact checksum conflict: ${artifact.packageName}" >&2; exit 1; }
      ''}
      install -m 0644 "$source" "$destination"
      cat > "$temporary/metadata/${artifact.packageName}.yml" <<EOF
AutoName: ${artifact.packageName}
Categories: [Connectivity]
License: Unknown
Summary: ${artifact.versionName}
Description: |
  ${artifact.versionName}
RepoType: git
SourceCode: https://example.invalid/${artifact.packageName}
Builds: []
EOF
    '') artifacts}
    cat > "$temporary/config.yml" <<EOF
repo_url: ${cfg.baseUrl}
repo_name: ${cfg.name}
repo_description: ${cfg.description}
repo_keyalias: ${cfg.signing.keyAlias}
keystore: $temporary/keystore
keystorepass: $(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.signing.passwordFile})
keypass: $(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.signing.passwordFile})
accepted_formats: [apk]
EOF
    [ -r ${lib.escapeShellArg cfg.signing.keystoreFile} ] || { echo "F-Droid keystore is unavailable" >&2; exit 1; }
    [ -s ${lib.escapeShellArg cfg.signing.passwordFile} ] || { echo "F-Droid keystore password file is unavailable" >&2; exit 1; }
    install -m 0600 ${lib.escapeShellArg cfg.signing.keystoreFile} "$temporary/keystore"
    (cd "$temporary" && ${pkgs.fdroidserver}/bin/fdroid update --create-metadata --clean --no-color)
    ${pkgs.jq}/bin/jq -n --argjson repository ${lib.escapeShellArg repositoryLedger} \
      '$repository | .schema_version = 1' > "$temporary/ledger.json"
    rm -f "$temporary/ledger.json.tmp"
    rm -rf "$state/.publish"
    mv "$temporary/repo" "$state/.publish"
    mv "$temporary/ledger.json" "$state/ledger.json"
    rm -rf "$repo"
    mv "$state/.publish" "$repo"
    install -m 0640 /dev/null "$state/.ready"
  '';
in
{
  options.services.osmium.fdroidRepository = {
    enable = lib.mkEnableOption "the Osmium F-Droid repository service";
    stateDir = lib.mkOption { type = lib.types.str; default = "/var/lib/fdroid-repository"; description = "Persistent repository state directory."; };
    repositoryId = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "osmium"; description = "Stable repository identity."; };
    name = lib.mkOption { type = lib.types.str; default = "Osmium F-Droid Repository"; description = "Repository display name."; };
    description = lib.mkOption { type = lib.types.str; default = "Applications published by Osmium."; description = "Repository description."; };
    baseUrl = lib.mkOption { type = lib.types.strMatching "https?://[^[:space:]]+/repo"; description = "Stable client-facing repository URL ending in /repo."; };
    guestPort = lib.mkOption { type = lib.types.port; default = 8080; description = "Guest HTTP port."; };
    hostPort = lib.mkOption { type = lib.types.port; default = 8080; description = "MicroVM host-forwarded HTTP port."; };
    artifacts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          packageName = lib.mkOption { type = lib.types.strMatching "[A-Za-z][A-Za-z0-9_.]+"; description = "Stable Android package identity."; };
          versionCode = lib.mkOption { type = lib.types.ints.positive; description = "Android version code."; };
          versionName = lib.mkOption { type = lib.types.str; description = "Displayed version name."; };
          path = lib.mkOption { type = lib.types.path; description = "Immutable APK input path."; };
          sha256 = lib.mkOption { type = lib.types.nullOr (lib.types.strMatching "[0-9a-fA-F]{64}"); default = null; description = "Expected APK SHA-256."; };
        };
      }));
      default = { };
      description = "Prebuilt APK artifacts copied into the repository.";
    };
    signing = {
      keystoreFile = lib.mkOption { type = lib.types.path; description = "Runtime path to the signing keystore."; };
      passwordFile = lib.mkOption { type = lib.types.path; description = "Runtime path to the keystore password."; };
      keyAlias = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "fdroid"; description = "Keystore alias."; };
    };
    reverseConfiguration = { enable = lib.mkEnableOption "review-only F-Droid reverse configuration tooling"; };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = lib.hasPrefix "/var/lib/" cfg.stateDir; message = "fdroidRepository.stateDir must be below /var/lib."; }
      { assertion = lib.hasSuffix "/repo" cfg.baseUrl; message = "F-Droid baseUrl must end in /repo for fdroidserver compatibility."; }
      { assertion = artifacts != [ ]; message = "F-Droid repository requires at least one APK artifact."; }
      { assertion = lib.length (lib.unique (map (artifact: "${artifact.packageName}:${toString artifact.versionCode}") artifacts)) == lib.length artifacts; message = "F-Droid artifact package/version identities must be unique."; }
      { assertion = lib.all (artifact: !(lib.hasInfix "/" artifact.packageName) && !(lib.hasInfix ".." artifact.packageName)) artifacts; message = "F-Droid artifact package identities must not contain path separators."; }
    ];
    users.users.fdroid = { isSystemUser = true; group = "fdroid"; home = stateDir; createHome = true; };
    users.groups.fdroid = { };
    environment.systemPackages = [ tool ];
    environment.persistence."/persistent".directories = [ { directory = stateDir; user = "fdroid"; group = "fdroid"; mode = "0750"; } ];
    systemd.services.osmium-fdroid-repository-generate = {
      description = "Generate the Osmium F-Droid repository";
      wantedBy = [ "multi-user.target" ];
      before = [ "osmium-fdroid-repository.service" ];
      path = [ pkgs.jdk pkgs.fdroidserver pkgs.coreutils pkgs.jq ];
      unitConfig.ConditionPathExists = "!${readyMarker}";
      serviceConfig = { Type = "oneshot"; User = "fdroid"; Group = "fdroid"; UMask = "0077"; ExecStart = generation; };
    };
    systemd.services.osmium-fdroid-repository = {
      description = "Serve the Osmium F-Droid repository";
      wantedBy = [ "multi-user.target" ];
      after = [ "osmium-fdroid-repository-generate.service" ];
      requires = [ "osmium-fdroid-repository-generate.service" ];
      serviceConfig = { User = "fdroid"; Group = "fdroid"; WorkingDirectory = stateDir; ExecStart = "${pkgs.python3}/bin/python -m http.server ${toString cfg.guestPort} --bind 0.0.0.0 --directory ${stateDir}"; Restart = "on-failure"; };
    };
  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = [ { from = "host"; proto = "tcp"; host.port = cfg.hostPort; guest.port = cfg.guestPort; } ];
  });
}
