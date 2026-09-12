{ pkgs, module, microvm }:

let
  adminPassword = "capture-admin-password";
  userPassword = "capture-user-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-gitea-repository-live-capture-reverse-configuration";
  nodes = {
    client = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "rcap-cli"; mac = "02:00:00:00:00:09"; } ]; };
      services.osmium.gitea = { enable = true; remoteCapture.enable = true; };
      environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openssh pkgs.sshpass ];
      environment.etc."fake-ssh" = { mode = "0755"; text = ''
        #!${pkgs.runtimeShell}
        exec ${pkgs.sshpass}/bin/sshpass -p capture-ssh-password ${pkgs.openssh}/bin/ssh -4 -o BatchMode=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$@"
      ''; };
      environment.variables.PATH = "/etc:/run/current-system/sw/bin";
    };
    remote = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "repo-capture-vm"; mac = "02:00:00:00:00:0a"; } ]; };
      services.openssh = { enable = true; settings = { PasswordAuthentication = true; PermitRootLogin = "no"; }; };
      users.users.capture = { isNormalUser = true; initialPassword = "capture-ssh-password"; extraGroups = [ "gitea" ]; };
      services.osmium.gitea = { enable = true; remoteCapture.enable = true; admin = { enable = true; username = "capture-admin"; email = "capture-admin@example.com"; passwordFile = "/etc/gitea-admin-password"; }; };
      environment.etc."gitea-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
      environment.etc."gitea-capture-credential" = { text = "${adminPassword}\n"; mode = "0400"; user = "capture"; group = "users"; };
      environment.variables = { OSMIUM_GITEA_API_URL = "http://127.0.0.1:3000/api/v1"; OSMIUM_GITEA_API_USERNAME = "capture-admin"; OSMIUM_GITEA_API_TOKEN_FILE = "/etc/gitea-capture-credential"; };
      environment.systemPackages = [ pkgs.curl pkgs.gitea pkgs.jq ];
    };
  };
  testScript = ''
    start_all()
    remote.wait_for_unit("gitea.service")
    remote.wait_for_unit("sshd.service")
    remote.wait_for_unit("osmium-gitea-admin-bootstrap.service")
    remote.succeed("runuser -u gitea -- gitea --config /var/lib/gitea/custom/conf/app.ini admin user create --username captured-user --password ${userPassword} --email captured-user@example.com --must-change-password=false")
    remote.succeed("curl --fail --user capture-admin:${adminPassword} -X POST http://127.0.0.1:3000/api/v1/admin/users/captured-user/orgs -H 'Content-Type: application/json' -d '{\"username\":\"captured-org\",\"description\":\"Runtime organization\",\"visibility\":\"private\"}'")
    remote.succeed("curl --fail --user captured-user:${userPassword} -X POST http://127.0.0.1:3000/api/v1/user/repos -H 'Content-Type: application/json' -d '{\"name\":\"user-repository\",\"description\":\"Runtime user repository\",\"private\":false,\"has_wiki\":false}'")
    remote.succeed("curl --fail --user capture-admin:${adminPassword} -X POST http://127.0.0.1:3000/api/v1/orgs/captured-org/repos -H 'Content-Type: application/json' -d '{\"name\":\"organization-repository\",\"description\":\"Runtime organization repository\",\"private\":false,\"has_issues\":true}'")
    remote.succeed("sha256sum /var/lib/gitea/custom/conf/app.ini > /tmp/capture-before.sha256")
    client.succeed("ssh-keyscan -4 -H remote > /tmp/known_hosts 2>/dev/null")
    client.succeed("/etc/fake-ssh -o UserKnownHostsFile=/tmp/known_hosts -o ExitOnForwardFailure=yes -N -L 4000:127.0.0.1:3000 capture@remote >/tmp/gitea-tunnel.log 2>&1 &")
    client.wait_for_open_port(4000)
    client.succeed("OSMIUM_SSH_COMMAND=/etc/fake-ssh osmium-gitea-remote capture --host remote --user capture --known-hosts /tmp/known_hosts --output /tmp/runtime-capture.json")
    client.succeed("OSMIUM_SSH_COMMAND=/etc/fake-ssh osmium-gitea-remote capture --host remote --user capture --known-hosts /tmp/known_hosts --output /tmp/runtime-capture-repeat.json && cmp /tmp/runtime-capture.json /tmp/runtime-capture-repeat.json")
    client.succeed("jq -e '.source.origin == \"observed\" and (.probes | any(.name == \"identities\" and .status == \"ok\")) and (.repositories | any(.[]; .owner_kind == \"user\" and .owner == \"captured-user\" and .name == \"user-repository\")) and (.repositories | any(.[]; .owner_kind == \"organization\" and .owner == \"captured-org\" and .name == \"organization-repository\"))' /tmp/runtime-capture.json")
    client.succeed("osmium-gitea-remote convert /tmp/runtime-capture.json --secret-file captured-user=/run/captured-user-password --output /tmp/runtime-candidate.json")
    client.succeed("jq -e '.activation_ready == false and .gitea.repositories.repository_captured_user_user_repository.owner.user == \"captured-user\" and .gitea.repositories.repository_captured_org_organization_repository.owner.organization == \"captured-org\" and .gitea.repositories.repository_captured_org_organization_repository.description == \"Runtime organization repository\"' /tmp/runtime-candidate.json")
    client.succeed("jq '.gitea.repositories.repository_captured_user_user_repository | {description, private, website, has_issues: .issues, has_wiki: .wiki, has_pull_requests: .pull_requests}' /tmp/runtime-candidate.json > /tmp/user-repository-reconciliation-payload.json")
    client.succeed("jq '.gitea.repositories.repository_captured_org_organization_repository | {description, private, website, has_issues: .issues, has_wiki: .wiki, has_pull_requests: .pull_requests}' /tmp/runtime-candidate.json > /tmp/org-repository-reconciliation-payload.json")
    client.succeed("OSMIUM_SSH_COMMAND=/etc/fake-ssh osmium-gitea-remote normalize /tmp/runtime-capture.json > /tmp/runtime-capture-normalized.json && cmp /tmp/runtime-capture.json /tmp/runtime-capture-normalized.json")
    client.succeed("jq '.repositories[0].unsupported = [\"repository-content\"]' /tmp/runtime-capture.json > /tmp/unsupported-capture.json && osmium-gitea-remote convert /tmp/unsupported-capture.json > /tmp/unsupported-candidate.json && jq -e '.activation_ready == false and any(.findings[]; .code == \"unsupported-state\")' /tmp/unsupported-candidate.json")
    client.succeed("jq '.repositories[0].owner_kind = \"ambiguous\"' /tmp/runtime-capture.json > /tmp/ambiguous-capture.json && osmium-gitea-remote convert /tmp/ambiguous-capture.json > /tmp/ambiguous-candidate.json && jq -e '.activation_ready == false and any(.findings[]; .code == \"ambiguous-owner\")' /tmp/ambiguous-candidate.json")
    client.succeed("! grep -E -i 'capture-admin-password|capture-user-password|token|secret|private-key' /tmp/runtime-capture.json /tmp/runtime-candidate.json")
    remote.succeed("sha256sum -c /tmp/capture-before.sha256")
    remote.succeed("curl --fail --user captured-user:${userPassword} http://127.0.0.1:3000/api/v1/repos/captured-user/user-repository | jq -e '.description == \"Runtime user repository\"'")
    remote.succeed("curl --fail --user capture-admin:${adminPassword} http://127.0.0.1:3000/api/v1/repos/captured-org/organization-repository | jq -e '.owner.login == \"captured-org\"'")
    client.succeed("curl --fail --user capture-admin:${adminPassword} -X PATCH http://127.0.0.1:4000/api/v1/repos/captured-user/user-repository -H 'Content-Type: application/json' --data-binary @/tmp/user-repository-reconciliation-payload.json | jq -e '.owner.login == \"captured-user\" and .description == \"Runtime user repository\"'")
    client.succeed("curl --fail --user capture-admin:${adminPassword} -X PATCH http://127.0.0.1:4000/api/v1/repos/captured-org/organization-repository -H 'Content-Type: application/json' --data-binary @/tmp/org-repository-reconciliation-payload.json | jq -e '.owner.login == \"captured-org\" and .description == \"Runtime organization repository\"'")
    client.shutdown()
    remote.shutdown()
  '';
}
