{ pkgs, module, microvm }:

let
  adminPassword = "drift-admin-password";
  ownerPassword = "drift-owner-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-gitea-repository-drift-reverse-configuration";

  nodes = {
    client = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = {
        hypervisor = "qemu";
        interfaces = [ { type = "user"; id = "repo-drift-cli"; mac = "02:00:00:00:00:07"; } ];
      };
      services.osmium.gitea = { enable = true; remoteCapture.enable = true; };
      environment.systemPackages = [ pkgs.jq pkgs.openssh pkgs.sshpass ];
      environment.etc."fake-ssh" = {
        mode = "0755";
        text = ''
          #!${pkgs.runtimeShell}
          exec ${pkgs.sshpass}/bin/sshpass -p capture-ssh-password ${pkgs.openssh}/bin/ssh -4 -o BatchMode=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$@"
        '';
      };
      environment.variables.PATH = "/etc:/run/current-system/sw/bin";
    };

    remote = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = {
        hypervisor = "qemu";
        interfaces = [ { type = "user"; id = "repo-drift-vm"; mac = "02:00:00:00:00:08"; } ];
      };
      services.openssh = {
        enable = true;
        settings = { PasswordAuthentication = true; PermitRootLogin = "no"; };
      };
      users.users.capture = { isNormalUser = true; initialPassword = "capture-ssh-password"; extraGroups = [ "gitea" ]; };
      services.osmium.gitea = {
        enable = true;
        remoteCapture.enable = true;
        driftDetection.enable = true;
        admin = { enable = true; username = "drift-admin"; email = "drift-admin@example.com"; passwordFile = "/etc/gitea-admin-password"; };
        users.declared-owner = { username = "declared-owner"; email = "declared-owner@example.com"; passwordFile = "/run/declared-owner-password"; };
        repositories.declared = {
          owner.user = "declared-owner";
          name = "runtime-repository";
          description = "Declared metadata";
          private = false;
          website = "https://example.invalid/declared";
          issues = true;
          wiki = false;
          pullRequests = true;
        };
      };
      environment.etc."gitea-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
      environment.etc."gitea-capture-credential" = { text = "${adminPassword}\n"; mode = "0400"; user = "capture"; group = "users"; };
      environment.variables = {
        OSMIUM_GITEA_API_URL = "http://127.0.0.1:3000/api/v1";
        OSMIUM_GITEA_API_USERNAME = "drift-admin";
        OSMIUM_GITEA_API_TOKEN_FILE = "/etc/gitea-capture-credential";
      };
      environment.systemPackages = [ pkgs.curl pkgs.gitea pkgs.jq ];
    };
  };

  testScript = ''
    start_all()
    remote.wait_for_unit("gitea.service")
    remote.wait_for_unit("sshd.service")
    remote.wait_for_unit("osmium-gitea-admin-bootstrap.service")
    remote.succeed("printf '${ownerPassword}\\n' > /run/declared-owner-password")
    remote.succeed("systemctl reset-failed osmium-gitea-repositories.service osmium-gitea-identities.service; systemctl start osmium-gitea-identities.service; systemctl start osmium-gitea-repositories.service")
    remote.succeed("curl --fail --user declared-owner:${ownerPassword} http://127.0.0.1:3000/api/v1/repos/declared-owner/runtime-repository | jq -e '.owner.login == \"declared-owner\" and .description == \"Declared metadata\"'")
    remote.succeed("curl --fail --user declared-owner:${ownerPassword} -X POST http://127.0.0.1:3000/api/v1/user/repos -H 'Content-Type: application/json' -d '{\"name\":\"content-preserved\"}'")
    remote.succeed("curl --fail --user declared-owner:${ownerPassword} -X PUT http://127.0.0.1:3000/api/v1/repos/declared-owner/content-preserved/contents/README.md -H 'Content-Type: application/json' -d '{\"content\":\"Y29udGVudC1tYXJrZXJcCg==\",\"message\":\"seed content\"}'")
    remote.succeed("curl --fail --user drift-admin:${adminPassword} -X PATCH http://127.0.0.1:3000/api/v1/repos/declared-owner/runtime-repository -H 'Content-Type: application/json' -d '{\"description\":\"Runtime metadata\",\"website\":\"https://example.invalid/runtime\"}'")
    remote.succeed("sha256sum /var/lib/gitea/custom/conf/app.ini > /tmp/repo-drift-before.sha256")
    remote.succeed("runuser -u gitea -- osmium-gitea-drift --json > /tmp/runtime-drift-report.json")
    remote.succeed("jq -e 'any(.classifications[]; .kind == \"changed\" and .resource == \"repository\" and .owner == \"declared-owner\" and .name == \"runtime-repository\" and any(.differences[]; .field == \"description\")) and any(.repositories[]; .name == \"content-preserved\")' /tmp/runtime-drift-report.json")
    remote.succeed("jq '{declared: .declared_repositories, observed: .repositories}' /tmp/runtime-drift-report.json > /tmp/runtime-drift-input.json")
    remote.succeed("runuser -u gitea -- osmium-gitea-remote drift /tmp/runtime-drift-input.json > /tmp/repository-drift.json")
    remote.succeed("runuser -u gitea -- osmium-gitea-remote convert-drift /tmp/repository-drift.json --output /tmp/repository-candidate.json")
    remote.succeed("runuser -u gitea -- osmium-gitea-remote convert-drift /tmp/repository-drift.json --output /tmp/repository-candidate-repeat.json && cmp /tmp/repository-candidate.json /tmp/repository-candidate-repeat.json")
    remote.succeed("jq -e '.complete == true and .activation_ready == true and .gitea.repositories.repository_declared_owner_runtime_repository.owner.user == \"declared-owner\" and .gitea.repositories.repository_declared_owner_runtime_repository.description == \"Runtime metadata\"' /tmp/repository-candidate.json")
    remote.succeed("! grep -E -i 'drift-admin-password|owner-password|token|secret|private-key' /tmp/runtime-drift-input.json /tmp/repository-drift.json /tmp/repository-candidate.json")
    remote.succeed("jq -e '.gitea.repositories.repository_declared_owner_runtime_repository | {description, website}' /tmp/repository-candidate.json > /tmp/repository-reconciliation-payload.json")
    remote.succeed("curl --fail --user drift-admin:${adminPassword} -X PATCH http://127.0.0.1:3000/api/v1/repos/declared-owner/runtime-repository -H 'Content-Type: application/json' --data-binary @/tmp/repository-reconciliation-payload.json | jq -e '.description == \"Runtime metadata\" and .website == \"https://example.invalid/runtime\"'")
    remote.succeed("jq '(.observed[] | select(.name == \"runtime-repository\")).unsupported = [\"repository-content\"]' /tmp/runtime-drift-input.json > /tmp/unsupported-drift-input.json && runuser -u gitea -- osmium-gitea-remote drift /tmp/unsupported-drift-input.json > /tmp/unsupported-drift.json && runuser -u gitea -- osmium-gitea-remote convert-drift /tmp/unsupported-drift.json --output /tmp/unsupported-candidate.json")
    remote.succeed("jq -e '.activation_ready == false and any(.findings[]; .code == \"unsupported-state\")' /tmp/unsupported-candidate.json")
    remote.succeed("jq '(.observed[] | select(.name == \"runtime-repository\")).owner_kind = \"organization\"' /tmp/runtime-drift-input.json > /tmp/owner-conflict-input.json && runuser -u gitea -- osmium-gitea-remote drift /tmp/owner-conflict-input.json > /tmp/owner-conflict.json && jq -e 'any(.changes[]; .classification == \"owner-conflict\") and .complete == false' /tmp/owner-conflict.json")
    remote.succeed("sha256sum -c /tmp/repo-drift-before.sha256")
    remote.succeed("curl --fail --user declared-owner:${ownerPassword} http://127.0.0.1:3000/api/v1/repos/declared-owner/content-preserved/contents/README.md | jq -r .content | tr -d '\\n\\r' | base64 -d | grep -F content-marker")
    remote.succeed("systemctl is-active gitea.service")
    client.succeed("ssh-keyscan -4 -H remote > /tmp/known_hosts 2>/dev/null")
    client.succeed("OSMIUM_SSH_COMMAND=/etc/fake-ssh osmium-gitea-remote capture --host remote --user capture --known-hosts /tmp/known_hosts > /tmp/capture-from-runtime.json")
    client.succeed("jq -e '.repositories | any(.[]; .owner == \"declared-owner\" and .name == \"runtime-repository\")' /tmp/capture-from-runtime.json")
    client.shutdown()
    remote.shutdown()
  '';
}
