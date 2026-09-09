{ pkgs, module, microvm }:

let
  capturePassword = "capture-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-remote-gitea-capture-real";

  nodes = {
    client = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = {
        hypervisor = "qemu";
        interfaces = [ { type = "user"; id = "capture-client"; mac = "02:00:00:00:00:05"; } ];
      };
      services.osmium.gitea = {
        enable = true;
        remoteCapture.enable = true;
      };
      environment.systemPackages = [ pkgs.jq pkgs.openssh pkgs.sshpass ];
      environment.etc."fake-ssh" = {
        mode = "0755";
        text = ''
          #!${pkgs.runtimeShell}
          exec ${pkgs.sshpass}/bin/sshpass -p ${capturePassword} ${pkgs.openssh}/bin/ssh -4 -o BatchMode=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$@"
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
        interfaces = [ { type = "user"; id = "capture-remote"; mac = "02:00:00:00:00:06"; } ];
      };
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "no";
        };
      };
      users.users.capture = {
        isNormalUser = true;
        description = "Read-only capture account";
        initialPassword = capturePassword;
      };
      services.osmium.gitea = {
        enable = true;
        hostHttpPort = 3001;
        hostSshPort = 2224;
        remoteCapture.enable = true;
        settings.service.DISABLE_REGISTRATION = false;
        admin = {
          enable = true;
          username = "bootstrap-admin";
          email = "bootstrap-admin@example.com";
          passwordFile = "/etc/gitea-admin-password";
        };
      };
      environment.etc."gitea-admin-password" = {
        text = "test-admin-password\n";
        mode = "0400";
        user = "gitea";
        group = "gitea";
      };
      environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.gitea ];
    };
  };

  testScript = ''
    start_all()
    remote.wait_for_unit("gitea.service")
    remote.wait_for_unit("sshd.service")
    remote.wait_for_unit("osmium-gitea-admin-bootstrap.service")
    remote.succeed("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    remote.succeed("runuser -u gitea -- gitea --config /var/lib/gitea/custom/conf/app.ini admin user create --username externally-created --password externally-password --email externally@example.com --must-change-password=false")
    remote.succeed("curl --fail --user bootstrap-admin:test-admin-password -X POST http://127.0.0.1:3000/api/v1/admin/users/bootstrap-admin/orgs -H 'Content-Type: application/json' -d '{\"username\":\"externally-created-org\",\"description\":\"Created during remote capture test\",\"visibility\":\"private\"}'")
    remote.succeed("sha256sum /var/lib/gitea/custom/conf/app.ini /var/lib/gitea/data/gitea.db > /tmp/remote-before.sha256")
    client.succeed("ssh-keyscan -4 -H remote > /tmp/known_hosts 2>/dev/null")
    client.succeed("OSMIUM_SSH_COMMAND=/etc/fake-ssh osmium-gitea-remote capture --host remote --user capture --known-hosts /tmp/known_hosts --output /tmp/capture.json")
    client.succeed("osmium-gitea-remote convert /tmp/capture.json --output /tmp/candidate.json")
    client.succeed("jq -e '.schema == \"osmium.remote-gitea-capture\" and .service.stateDir == \"/var/lib/gitea\" and (.persistence | any(.path == \"/var/lib/gitea\")) and .complete == false' /tmp/capture.json")
    client.succeed("jq -e 'any(.findings[]; .code == \"unsupported-probe\" and .probe == \"identities\")' /tmp/capture.json")
    client.succeed("jq -e '.activation_ready == false and any(.findings[]; .code == \"unsupported-probe\")' /tmp/candidate.json")
    remote.succeed("sha256sum -c /tmp/remote-before.sha256")
    remote.succeed("curl --fail --user externally-created:externally-password http://127.0.0.1:3000/api/v1/user | jq -e '.login == \"externally-created\"'")
    remote.succeed("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/orgs/externally-created-org | jq -e '.username == \"externally-created-org\"'")
    remote.succeed("systemctl is-active gitea.service")
    client.shutdown()
    remote.shutdown()
  '';
}
