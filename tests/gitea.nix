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
    };
  };

  testScript = ''
    vm.start(allow_reboot=True)
    vm.wait_for_unit("gitea.service")
    ${healthchecks.http {
      name = "gitea-http-healthz";
      port = 3000;
      path = "/api/healthz";
      expectedStatus = 200;
    }}
    vm.succeed("curl --fail http://127.0.0.1:3000/api/healthz")
    vm.succeed("su -s /bin/sh gitea -c 'gitea --config /var/lib/gitea/custom/conf/app.ini admin user create --username test --password test-password --email test@example.com --admin --must-change-password=false'")
    vm.succeed("curl --fail --user test:test-password -X POST http://127.0.0.1:3000/api/v1/user/repos -H 'Content-Type: application/json' -d '{\"name\":\"persistent\"}'")
    vm.shutdown()
    vm.start()
    vm.wait_for_unit("gitea.service")
    vm.wait_for_open_port(3000)
    vm.succeed("curl --fail --user test:test-password http://127.0.0.1:3000/api/v1/user/repos | jq -e 'any(.[]; .name == \"persistent\")'")
    vm.succeed("test \"$(stat -c %U /var/lib/gitea)\" = gitea")
  '';
}
