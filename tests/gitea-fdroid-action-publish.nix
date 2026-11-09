{ pkgs, lib, module, microvm }:

let
  androidPkgs = import pkgs.path {
    system = pkgs.system;
    config = { allowUnfree = true; android_sdk.accept_license = true; };
  };
  androidSdk = androidPkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "35" ];
    buildToolsVersions = [ "35.0.0" ];
    includeEmulator = false;
    includeNDK = false;
  };
  publicationKey = ./fixtures/gitea-fdroid-action/publication-key;
  fdroidHostKey = ./fixtures/gitea-fdroid-action/fdroid-host-key;
  fdroidKnownHost = ./fixtures/gitea-fdroid-action/fdroid-host-known-hosts;
  publisherShell = pkgs.writeShellScriptBin "fdroid-publisher-shell" ''
     set -u
     command="''${SSH_ORIGINAL_COMMAND-}"
     if [ -z "$command" ] && [ "''${1-}" = "-c" ]; then
       command="''${2-}"
     fi
     printf 'publisher-shell: uid=%s argc=%s command=<%s>\n' "$UID" "$#" "$command" >&2
     printf '%s' "$command" | ${pkgs.coreutils}/bin/od -An -tx1 >&2
     case "$command" in
       "cat > /var/lib/fdroid-repository/incoming/org.osmium.actiontest_1.apk"*)
         printf 'publisher-shell: upload branch, destination=%s\n' /var/lib/fdroid-repository/incoming/org.osmium.actiontest_1.apk >&2
         ${pkgs.coreutils}/bin/cat > /var/lib/fdroid-repository/incoming/org.osmium.actiontest_1.apk
         status=$?
         printf 'publisher-shell: upload exit=%s\n' "$status" >&2
         exit "$status"
         ;;
       *)
         printf 'publisher-shell: rejected command\n' >&2
         exit 1
         ;;
     esac
  '';
  adminPassword = "action-admin-password";
  publisherPassword = "action-publisher-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-gitea-fdroid-action-publish";

  nodes = {
    gitea = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = {
        hypervisor = "qemu";
        vcpu = 2;
        mem = 2048;
        interfaces = [ { type = "user"; id = "action-gitea"; mac = "02:00:00:00:00:21"; } ];
      };
      virtualisation.graphics = false;
      services.osmium.gitea = {
        enable = true;
        hostHttpPort = 3011;
        hostSshPort = 2231;
         settings.actions.ENABLED = true;
         settings.server.START_SSH_SERVER = true;
        settings.service.DISABLE_REGISTRATION = false;
        admin = { enable = true; username = "action-admin"; email = "action-admin@example.com"; passwordFile = "/etc/action-admin-password"; };
        users.publisher = { username = "action-publisher"; email = "action-publisher@example.com"; passwordFile = "/etc/action-publisher-password"; };
        repositories.action-source = { owner.user = "action-publisher"; name = "action-source"; private = false; defaultBranch = "main"; };
        credentials.source-deploy = {
          kind = "deploy-key";
          repository = { owner.user = "action-publisher"; name = "action-source"; };
          accessMode = "read-write";
          output = { secretPath = "/var/lib/gitea/credentials/source-deploy.key"; publicPath = "/var/lib/gitea/credentials/source-deploy.json"; owner = "gitea"; group = "gitea"; mode = "0400"; };
        };
      };
      environment.variables.ANDROID_HOME = "${androidSdk.androidsdk}";
      environment.etc."action-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
      environment.etc."action-publisher-password" = { text = "${publisherPassword}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
      environment.etc."gitea-action-manifest" = { source = ./fixtures/gitea-fdroid-action/AndroidManifest.xml; mode = "0444"; };
      environment.etc."gitea-action-workflow" = { source = ./fixtures/gitea-fdroid-action/publish.yaml; mode = "0444"; };
      environment.etc."fdroid-publication-key" = { source = publicationKey; mode = "0400"; user = "gitea-runner"; group = "gitea-runner"; };
      environment.etc."fdroid-known-host" = { source = fdroidKnownHost; mode = "0400"; user = "gitea-runner"; group = "gitea-runner"; };
      users.users.gitea-runner = { isSystemUser = true; group = "gitea-runner"; home = "/var/lib/gitea-runner"; createHome = true; };
      users.groups.gitea-runner = { };
      environment.systemPackages = [ pkgs.curl pkgs.git pkgs.jq pkgs.openssh pkgs.sudo ];
      systemd.services.gitea-runner-token = {
        wantedBy = [ "multi-user.target" ];
        after = [ "gitea.service" "osmium-gitea-admin-bootstrap.service" ];
        requires = [ "gitea.service" "osmium-gitea-admin-bootstrap.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; Group = "root"; };
        path = [ pkgs.curl pkgs.jq ];
        script = ''
          install -d -m 0700 /run/gitea-runner
           set -o pipefail
           token="$(curl --fail --silent --user action-admin:${adminPassword} -X POST http://127.0.0.1:3000/api/v1/admin/actions/runners/registration-token | jq -r .token)"
           test -n "$token" && test "$token" != null
           printf '%s\n' "$token" > /run/gitea-runner/TOKEN
          chmod 0400 /run/gitea-runner/TOKEN
        '';
      };
      environment.etc."runner-token-file" = { text = "TOKEN=\n"; mode = "0400"; };
      systemd.services.gitea-runner-action = {
        wantedBy = lib.mkForce [ ];
        after = [ "gitea-runner-token.service" "gitea-runner-env.service" ];
        requires = [ "gitea-runner-token.service" "gitea-runner-env.service" ];
        environment.ANDROID_HOME = "${androidSdk.androidsdk}";
        serviceConfig = { DynamicUser = lib.mkForce false; User = lib.mkForce "gitea-runner"; Group = lib.mkForce "gitea-runner"; EnvironmentFile = lib.mkForce "/run/gitea-runner/runner.env"; };
      };
      services.gitea-actions-runner.instances.action = {
        enable = true;
        name = "osmium-action-runner";
        url = "http://127.0.0.1:3000";
        tokenFile = "/run/gitea-runner/runner.env";
         labels = [ "native:host" ];
        settings.log.level = "debug";
        hostPackages = [ pkgs.bash androidSdk.androidsdk pkgs.jdk pkgs.openssh pkgs.curl pkgs.git pkgs.apksigner ];
      };
      systemd.services.gitea-runner-env = {
         before = [ "gitea-runner-action.service" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "gitea-runner-token.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; };
        script = ''
          install -d -m 0700 /run/gitea-runner
          chown gitea-runner:gitea-runner /run/gitea-runner
          install -m 0400 -o gitea-runner -g gitea-runner /dev/null /run/gitea-runner/apk.password
          printf 'action-apk-password\n' > /run/gitea-runner/apk.password
          ${pkgs.jdk}/bin/keytool -genkeypair -keystore /run/gitea-runner/apk.keystore -storepass action-apk-password -keypass action-apk-password -alias actiontest -dname CN=OsmiumActionTest -keyalg RSA -validity 3650 -noprompt
          cp /etc/fdroid-publication-key /run/gitea-runner/publish.key
          cp /etc/fdroid-known-host /run/gitea-runner/fdroid_known_hosts
          chown gitea-runner:gitea-runner /run/gitea-runner/*
          chmod 0400 /run/gitea-runner/*
          printf 'TOKEN=%s\n' "$(cat /run/gitea-runner/TOKEN)" > /run/gitea-runner/runner.env
          chown gitea-runner:gitea-runner /run/gitea-runner/runner.env
        '';
      };
      systemd.services.gitea.serviceConfig.TimeoutStartSec = lib.mkForce "10min";
      systemd.services.gitea-seed-action = {
        wantedBy = [ "multi-user.target" ];
        after = [ "osmium-gitea-credentials.service" "gitea-runner-action.service" "gitea-runner-env.service" ];
        requires = [ "osmium-gitea-credentials.service" "gitea-runner-action.service" ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; Group = "root"; };
         path = [ pkgs.git pkgs.openssh ];
         script = ''
           for attempt in $(seq 1 120); do
             ssh-keyscan -T 1 -4 -p 2222 127.0.0.1 >/dev/null 2>&1 && break
             sleep 1
           done
           ssh-keyscan -T 1 -4 -p 2222 127.0.0.1 >/dev/null 2>&1
           ssh-keyscan -4 -H -p 2222 127.0.0.1 > /tmp/gitea_known_hosts 2>/dev/null
           rm -rf /tmp/action-source
           GIT_SSH_COMMAND='ssh -o BatchMode=yes -o UserKnownHostsFile=/tmp/gitea_known_hosts -i /var/lib/gitea/credentials/source-deploy.key' git clone ssh://gitea@127.0.0.1:2222/action-publisher/action-source /tmp/action-source
          install -d /tmp/action-source/.gitea/workflows
          cp /etc/gitea-action-manifest /tmp/action-source/AndroidManifest.xml
          cp /etc/gitea-action-workflow /tmp/action-source/.gitea/workflows/publish.yaml
          git -C /tmp/action-source config user.name action-seeder
          git -C /tmp/action-source config user.email action-seeder@example.com
           git -C /tmp/action-source add .
           git -C /tmp/action-source commit -m trigger-action
            GIT_SSH_COMMAND='ssh -o BatchMode=yes -o UserKnownHostsFile=/tmp/gitea_known_hosts -i /var/lib/gitea/credentials/source-deploy.key' git -C /tmp/action-source push origin HEAD:main
         '';
      };
      networking.firewall.allowedTCPPorts = [ 3000 2222 ];
    };

    fdroid = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; vcpu = 1; mem = 768; interfaces = [ { type = "user"; id = "action-fdroid"; mac = "02:00:00:00:00:22"; } ]; };
      virtualisation.graphics = false;
      services.openssh = { enable = true; hostKeys = [ { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; } ]; };
      environment.etc."fdroid-host-key" = { source = fdroidHostKey; mode = "0444"; };
      systemd.services.fdroid-install-host-key = {
        wantedBy = [ "multi-user.target" ];
        before = [ "sshd-keygen.service" "sshd.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; };
        script = ''
          install -d -m 0755 /etc/ssh
          install -m 0600 /etc/fdroid-host-key /etc/ssh/ssh_host_ed25519_key
        '';
      };
      systemd.services.sshd = {
        after = [ "fdroid-install-host-key.service" ];
        requires = [ "fdroid-install-host-key.service" ];
      };
      users.users.fdroid-publisher = { isNormalUser = true; home = "/var/lib/fdroid-publisher"; createHome = true; openssh.authorizedKeys.keys = [ (builtins.readFile ./fixtures/gitea-fdroid-action/publication-key.pub) ]; shell = "${publisherShell}/bin/fdroid-publisher-shell"; };
       systemd.paths.fdroid-action-publish = {
         wantedBy = [ "multi-user.target" ];
         pathConfig = {
           PathExists = "/var/lib/fdroid-repository/incoming/org.osmium.actiontest_1.apk";
           Unit = "osmium-fdroid-repository.service";
         };
       };
      services.osmium.fdroidRepository = { enable = true; repositoryId = "action-repository"; name = "Action Repository"; description = "Published by Gitea Actions"; baseUrl = "http://fdroid:8080/repo"; guestPort = 8080; hostPort = 38081; artifacts.actiontest = { packageName = "org.osmium.actiontest"; versionCode = 1; versionName = "1.0"; path = "/var/lib/fdroid-repository/incoming/org.osmium.actiontest_1.apk"; }; signing = { keystoreFile = "/run/fdroid/keystore"; passwordFile = "/run/fdroid/password"; keyAlias = "fdroid"; }; };
      systemd.services.osmium-fdroid-repository-generate.wantedBy = lib.mkForce [ ];
      systemd.services.osmium-fdroid-repository.wantedBy = lib.mkForce [ ];
      systemd.services.fdroid-action-secret = { before = [ "osmium-fdroid-repository-generate.service" ]; wantedBy = [ "multi-user.target" ]; serviceConfig = { Type = "oneshot"; }; script = ''
         install -d -m 0700 /run/fdroid /var/lib/fdroid-repository/incoming
         chmod 0755 /var/lib/fdroid-repository
        printf 'fdroid-index-password\n' > /run/fdroid/password
        ${pkgs.jdk}/bin/keytool -genkeypair -keystore /run/fdroid/keystore -storepass fdroid-index-password -keypass fdroid-index-password -alias fdroid -dname CN=fdroid -keyalg RSA -validity 3650 -noprompt
         chown -R fdroid:fdroid /run/fdroid /var/lib/fdroid-repository/incoming
         chmod 0773 /var/lib/fdroid-repository/incoming
         chmod 0400 /run/fdroid/password /run/fdroid/keystore
      ''; };
       environment.systemPackages = [ pkgs.apksigner pkgs.curl pkgs.jq pkgs.fdroidserver pkgs.jdk pkgs.openssh ];
      networking.firewall.allowedTCPPorts = [ 22 8080 ];
    };
  };

  testScript = ''
    start_all()
    gitea.wait_for_unit("gitea.service")
    gitea.wait_for_unit("gitea-runner-action.service")
    fdroid.wait_for_unit("sshd.service")
    fdroid.succeed("test ! -e /var/lib/fdroid-repository/incoming/org.osmium.actiontest_1.apk")
    fdroid.succeed("! curl --fail --silent http://127.0.0.1:8080/repo/index-v2.json")
    fdroid.succeed("! ssh -4 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /etc/ssh/ssh_host_ed25519_key fdroid-publisher@127.0.0.1 true")
    gitea.succeed("awk '/apksigner verify/{verified=1} /ssh -4/{if (!verified) exit 1}' /etc/gitea-action-workflow")
    gitea.wait_for_unit("gitea-seed-action.service")
    gitea.succeed("sleep 30")
    gitea.succeed("test -e /var/lib/gitea-runner/action/osmium-action-started")
    gitea.succeed("curl --fail --silent --user action-admin:${adminPassword} http://127.0.0.1:3000/api/v1/repos/action-publisher/action-source/actions/runs | jq .")
    gitea.succeed("curl --fail --silent --user action-admin:${adminPassword} http://127.0.0.1:3000/api/v1/repos/action-publisher/action-source/actions/runs | jq -e 'any(.workflow_runs[]?; (.status == \"success\") or (.status == \"completed\" and (.conclusion == \"success\" or .result == \"success\")))'")
    fdroid.wait_for_unit("osmium-fdroid-repository.service")
    fdroid.wait_for_open_port(8080)
    fdroid.succeed("curl --fail http://127.0.0.1:8080/repo/index-v2.json -o /tmp/index.json")
    fdroid.succeed("jq -e 'has(\"packages\") and (.packages | has(\"org.osmium.actiontest\")) and any(.packages[\"org.osmium.actiontest\"] | .. | objects; (.versionCode? == 1) or (.versionCode? == \"1\"))' /tmp/index.json")
    fdroid.succeed("curl --fail http://127.0.0.1:8080/repo/org.osmium.actiontest_1.apk -o /tmp/actiontest.apk")
    fdroid.succeed("apksigner verify --print-certs /tmp/actiontest.apk | grep -F 'Signer #1 certificate DN: CN=OsmiumActionTest'")
    fdroid.succeed("sha256=$(sha256sum /tmp/actiontest.apk | cut -d' ' -f1); jq --arg sha \"$sha256\" -e 'any(.packages[\"org.osmium.actiontest\"] | .. | objects; .sha256? == $sha)' /tmp/index.json")
    fdroid.succeed("curl --fail http://127.0.0.1:8080/repo/index-v1.jar -o /tmp/index-v1.jar && jarsigner -verify /tmp/index-v1.jar >/tmp/index-v1-verify.txt")
    gitea.succeed("! grep -E -i 'action-apk-password|fdroid-index-password|BEGIN (OPENSSH|PRIVATE) KEY' /var/lib/gitea-runner /var/log/messages || true")
    gitea.shutdown()
    fdroid.shutdown()
  '';
}
