{ pkgs, module, microvm }:

pkgs.testers.runNixOSTest {
  name = "osmium-remote-gitea-capture";

  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      interfaces = [ { type = "user"; id = "remote-capture"; mac = "02:00:00:00:00:04"; } ];
    };
    services.osmium.gitea = {
      enable = true;
      remoteCapture.enable = true;
    };
    environment.systemPackages = [ pkgs.jq ];
    environment.etc."ssh/ssh_known_hosts".text = "";
    environment.etc."fake-bin/ssh" = {
      mode = "0755";
      text = ''
        #! /bin/sh
        probe=
        for arg do probe="$arg"; done
        case "$probe" in
          platform) printf '%s\n' '{"platform":"nixos"}' ;;
          service) printf '%s\n' '{"status":"ok","service":{"stateDir":"/var/lib/gitea","settings":{"service":{"DISABLE_REGISTRATION":false}},"paths":["/var/lib/gitea"]}}' ;;
          identities) printf '%s\n' '{"status":"ok","users":[{"username":"remote-user","email":"remote@example.com"}],"organizations":[{"name":"remote-org","owner":"remote-user","visibility":"private"}]}' ;;
          persistence) printf '%s\n' '{"status":"ok","paths":[{"path":"/var/lib/gitea","origin":"observed"}]}' ;;
          *) exit 64 ;;
        esac
      '';
    };
    environment.variables.PATH = "/etc/fake-bin:/run/current-system/sw/bin";
  };

  testScript = ''
    vm.start()
    vm.wait_for_unit("gitea.service")
    vm.succeed("OSMIUM_SSH_COMMAND=/etc/fake-bin/ssh osmium-gitea-remote capture --host remote.test --user capture --known-hosts /etc/ssh/ssh_known_hosts --output /tmp/capture.json")
    vm.succeed("OSMIUM_SSH_COMMAND=/etc/fake-bin/ssh osmium-gitea-remote capture --host remote.test --user capture --known-hosts /etc/ssh/ssh_known_hosts > /tmp/capture-repeat.json")
    vm.succeed("cmp /tmp/capture.json /tmp/capture-repeat.json")
    vm.succeed("osmium-gitea-remote convert /tmp/capture.json --secret-file remote-user=/run/remote-password --output /tmp/candidate.json")
    vm.succeed("jq -e '.complete == true and .gitea.users.user_remote_user.username == \"remote-user\" and .gitea.organizations.organization_remote_org.owner == \"remote-user\"' /tmp/candidate.json")
    vm.succeed("osmium-gitea-remote convert /tmp/capture.json --secret-file remote-user=/run/remote-password --output /tmp/candidate.nix")
    vm.succeed("grep -F 'user_remote_user' /tmp/candidate.nix")
    vm.succeed("grep -F 'organization_remote_org' /tmp/candidate.nix")
    vm.succeed("! grep -E -i 'test-password|password-value|access-token|private-key-bytes' /tmp/capture.json /tmp/candidate.json")
    vm.succeed("test -e /var/lib/gitea/custom/conf/app.ini")
    vm.shutdown()
  '';
}
