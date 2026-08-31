{ pkgs, module }:

pkgs.testers.runNixOSTest {
  name = "mythoclast-persistence";

  nodes.vm = {
    imports = [ module ];

    virtualisation.graphics = false;
    virtualisation.diskSize = 2048;
    environment.systemPackages = [ pkgs.curl ];

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

    services.mythoclast.hello = {
      enable = true;
      port = 8080;
    };
  };

  testScript = ''
    vm.start(allow_reboot=True)
    vm.wait_for_unit("mythoclast-hello.service")
    vm.wait_for_open_port(8080)
    vm.succeed("test -d /var/lib/mythoclast-hello")
    vm.succeed("echo persistent-state > /var/lib/mythoclast-hello/state")
    vm.succeed("curl --fail http://127.0.0.1:8080/state")
    vm.reboot()
    vm.wait_for_unit("mythoclast-hello.service")
    vm.wait_for_open_port(8080)
    vm.succeed("test \"$(cat /var/lib/mythoclast-hello/state)\" = persistent-state")
  '';
}
