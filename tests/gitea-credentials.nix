{ pkgs, lib, module, microvm }:

let
  adminPassword = "credential-admin-password";
  userPassword = "credential-user-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-gitea-credentials";

  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 1024;
      interfaces = [ { type = "user"; id = "gitea-creds"; mac = "02:00:00:00:00:0b"; } ];
    };
    services.osmium.gitea = {
      enable = true;
      settings.server.START_SSH_SERVER = true;
      admin = {
        enable = true;
        username = "credential-admin";
        email = "credential-admin@example.com";
        passwordFile = "/etc/gitea-admin-password";
      };
      users.owner = {
        username = "credential-owner";
        email = "credential-owner@example.com";
        passwordFile = "/etc/credential-owner-password";
      };
      repositories.credential-repository = {
        owner.user = "credential-owner";
        name = "credential-repository";
      };
      credentials.owner-read = {
        kind = "personal-token";
        username = "credential-owner";
        scopes = [ "read:user" "read:repository" ];
        output = {
          secretPath = "/var/lib/gitea/credentials/owner-read.token";
          publicPath = "/var/lib/gitea/credentials/owner-read.json";
          owner = "gitea";
          group = "gitea";
          mode = "0400";
          };
        };
      credentials.repository-deploy = {
        kind = "deploy-key";
        repository = {
          owner.user = "credential-owner";
          name = "credential-repository";
        };
        accessMode = "read-only";
        output = {
          secretPath = "/var/lib/gitea/credentials/repository-deploy.key";
          publicPath = "/var/lib/gitea/credentials/repository-deploy.json";
          owner = "gitea";
          group = "gitea";
          mode = "0400";
        };
      };
      credentials.oauth-application = {
        kind = "oauth-application";
        applicationName = "credential-oauth-application";
        callbackUrls = [ "https://client.example.test/callback" ];
        output = {
          secretPath = "/var/lib/gitea/credentials/oauth-application.secret";
          publicPath = "/var/lib/gitea/credentials/oauth-application.json";
          owner = "gitea";
          group = "gitea";
          mode = "0400";
        };
      };
    };
    environment.etc."gitea-admin-password" = {
      text = "${adminPassword}\n";
      mode = "0400";
      user = "gitea";
      group = "gitea";
    };
    environment.etc."credential-owner-password" = {
      text = "${userPassword}\n";
      mode = "0400";
      user = "gitea";
      group = "gitea";
    };
    environment.systemPackages = [ pkgs.curl pkgs.git pkgs.jq pkgs.openssh ];
  };

  testScript = ''
    start_all()
    vm.wait_for_unit("gitea.service")
    vm.wait_for_unit("osmium-gitea-admin-bootstrap.service")
    vm.wait_until_succeeds("test -f /var/lib/gitea/credentials/owner-read.token && test -f /var/lib/gitea/credentials/owner-read.json && test -f /var/lib/gitea/credentials/repository-deploy.key && test -f /var/lib/gitea/credentials/repository-deploy.json && test -f /var/lib/gitea/credentials/oauth-application.secret && test -f /var/lib/gitea/credentials/oauth-application.json")
    vm.succeed("test \"$(stat -c '%U:%G:%a' /var/lib/gitea/credentials/owner-read.token)\" = gitea:gitea:400")
    vm.succeed("jq -e '.schema_version == 1 and (.credentials | length) == 3 and any(.credentials[]; .declaration == \"owner-read\" and .status == \"success\" and (has(\"token\") | not)) and any(.credentials[]; .declaration == \"repository-deploy\" and .status == \"success\" and (.fingerprint | type) == \"string\") and any(.credentials[]; .declaration == \"oauth-application\" and .status == \"success\" and (.client_id | type) == \"string\" and (has(\"client_secret\") | not))' /var/lib/gitea/.osmium-credential-ledger.json")
    vm.succeed("jq -e '((.scopes // []) | sort) == ([\"read:user\",\"read:repository\"] | sort) and (.id | type) == \"number\" and (.token | not)' /var/lib/gitea/credentials/owner-read.json")
    vm.succeed("test -f /var/lib/gitea/credentials/repository-deploy.key && test -f /var/lib/gitea/credentials/repository-deploy.json && test \"$(stat -c '%U:%G:%a' /var/lib/gitea/credentials/repository-deploy.key)\" = gitea:gitea:400")
    vm.succeed("jq -e '.access_mode == \"read-only\" and (.id | type) == \"number\" and (.fingerprint | type) == \"string\" and (.key | type) == \"string\"' /var/lib/gitea/credentials/repository-deploy.json")
    vm.succeed("test \"$(stat -c '%U:%G:%a' /var/lib/gitea/credentials/oauth-application.secret)\" = gitea:gitea:400 && jq -e '(.client_id | type == \"string\" and . != \"\") and .name == \"credential-oauth-application\"' /var/lib/gitea/credentials/oauth-application.json")
    vm.succeed("curl --fail --silent --user credential-admin:${adminPassword} http://127.0.0.1:3000/api/v1/user/applications/oauth2 | jq -e 'any(.[]; .name == \"credential-oauth-application\" and .redirect_uris == [\"https://client.example.test/callback\"])'")
    vm.succeed("curl --fail --silent --user credential-admin:${adminPassword} http://127.0.0.1:3000/api/v1/repos/credential-owner/credential-repository/keys | jq -e 'any(.[]; .title == \"repository-deploy\" and .read_only == true)'")
    vm.succeed("GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /var/lib/gitea/credentials/repository-deploy.key' git clone ssh://gitea@127.0.0.1:2222/credential-owner/credential-repository /tmp/deploy-clone")
    vm.succeed("printf 'read-only-check\\n' > /tmp/deploy-clone/read-only-check && git -C /tmp/deploy-clone add read-only-check && git -C /tmp/deploy-clone -c user.name=test -c user.email=test@example.com commit -m read-only-check && ! GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /var/lib/gitea/credentials/repository-deploy.key' git -C /tmp/deploy-clone push origin HEAD:main")
    vm.succeed("curl --fail --silent -H \"Authorization: token $(cat /var/lib/gitea/credentials/owner-read.token)\" http://127.0.0.1:3000/api/v1/user | jq -e '.login == \"credential-owner\"'")
    vm.succeed("cp /var/lib/gitea/credentials/owner-read.token /tmp/token-before-restart && jq --arg d owner-read -r '.credentials[] | select(.declaration == $d) | .id' /var/lib/gitea/.osmium-credential-ledger.json > /tmp/id-before-restart")
    vm.succeed("systemctl restart osmium-gitea-credentials.service")
    vm.succeed("cmp /tmp/token-before-restart /var/lib/gitea/credentials/owner-read.token && test \"$(jq --arg d owner-read -r '.credentials[] | select(.declaration == $d) | .id' /var/lib/gitea/.osmium-credential-ledger.json)\" = \"$(cat /tmp/id-before-restart)\"")
    vm.succeed("! grep -E -i '${adminPassword}|${userPassword}|token_value|private_key|client_secret' /var/lib/gitea/.osmium-credential-ledger.json /var/log/messages || true")
    vm.shutdown()
  '';
}
