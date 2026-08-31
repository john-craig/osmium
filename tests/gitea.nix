{ pkgs, module, microvm, healthchecks }:

pkgs.testers.runNixOSTest {
  name = "mythoclast-gitea";

  nodes.vm = {
    imports = [
      microvm.nixosModules.microvm
      module
    ];

    nixpkgs.overlays = pkgs.lib.mkForce [ ];

    microvm = {
      hypervisor = "qemu";
      interfaces = [ {
        type = "user";
        id = "gitea-test";
        mac = "02:00:00:00:00:03";
      } ];
    };

    virtualisation.graphics = false;
    virtualisation.diskSize = 4096;
    environment.systemPackages = with pkgs; [
      curl
      gitea
      git
      jq
    ];

    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "mode=755" ];
      neededForBoot = true;
    };

    fileSystems."/persistent" = {
      device = "/dev/vda";
      fsType = "ext4";
      neededForBoot = true;
    };

    services.mythoclast.gitea = {
      enable = true;
      hostHttpPort = 3001;
      hostSshPort = 2223;
      settings.service.DISABLE_REGISTRATION = false;
      admin = {
        enable = true;
        username = "bootstrap-admin";
        email = "bootstrap-admin@example.com";
        passwordFile = "/etc/gitea-admin-password";
        rotation = {
          enable = true;
          passwordFile = "/run/gitea-admin-rotation-password";
          maxAge = 3600;
          checkInterval = 3600;
        };
      };
    };

    environment.etc."gitea-admin-password" = {
      text = "test-admin-password\n";
      mode = "0400";
      user = "gitea";
      group = "gitea";
    };
  };

  testScript = ''
    vm.start(allow_reboot=True)
    vm.wait_for_unit("gitea.service")
    vm.wait_for_unit("mythoclast-gitea-admin-bootstrap.service")
    ${healthchecks.http {
      name = "gitea-http-healthz";
      port = 3000;
      path = "/api/healthz";
      expectedStatus = 200;
    }}
    vm.succeed("curl --fail http://127.0.0.1:3000/api/healthz")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X POST http://127.0.0.1:3000/api/v1/user/repos -H 'Content-Type: application/json' -d '{\"name\":\"persistent\"}'")
    vm.succeed("printf 'rotated-admin-password\\n' > /run/gitea-admin-rotation-password")
    vm.succeed("systemctl restart mythoclast-gitea-admin-rotation.service")
    vm.fail("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/user")
    vm.succeed("curl --fail --user bootstrap-admin:rotated-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("rm /run/gitea-admin-rotation-password")
    vm.fail("systemctl restart mythoclast-gitea-admin-rotation.service", timeout=10)
    vm.succeed("curl --fail --user bootstrap-admin:rotated-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("printf 'recovered-admin-password\\n' > /run/gitea-admin-rotation-password && systemctl restart mythoclast-gitea-admin-rotation.service")
    vm.succeed("curl --fail --user bootstrap-admin:recovered-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.shutdown()
    vm.start()
    vm.wait_for_unit("gitea.service")
    vm.wait_for_open_port(3000)
    vm.succeed("curl --fail --user bootstrap-admin:recovered-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("curl --fail --user bootstrap-admin:recovered-admin-password http://127.0.0.1:3000/api/v1/user/repos | jq -e 'any(.[]; .name == \"persistent\")'")
    vm.succeed("test -e /var/lib/gitea/.mythoclast-admin-bootstrap-complete")
    vm.succeed("test \"$(stat -c %U /var/lib/gitea)\" = gitea")
  '';
}
