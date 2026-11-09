{ pkgs, module, microvm }:

let
  site = pkgs.writeTextDir "site/index.html" ''
    Traefik route reached
  '';
in
pkgs.testers.runNixOSTest {
  name = "osmium-traefik";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "traefikvm"; mac = "02:00:00:00:00:41"; } ];
    };

    services.osmium.traefik = {
      enable = true;
      entrypoints.web = { guestPort = 8000; hostPort = 38080; };
      environmentFiles = [ "/run/traefik-runtime.env" ];
      dynamicConfigOptions = {
        http.routers.site = {
          rule = "PathPrefix(`/`)";
          entryPoints = [ "web" ];
          service = "site";
        };
        http.services.site.loadBalancer.servers = [ { url = "http://127.0.0.1:9000"; } ];
      };
      dashboard.enable = true;
    };

    systemd.services.fixture-backend = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python -m http.server 9000 --directory ${site}/site";
        Restart = "on-failure";
        User = "nobody";
      };
    };
    systemd.services.traefik-runtime-env = {
      before = [ "traefik.service" ];
      wantedBy = [ "traefik.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        printf 'TRAEFIK_RUNTIME_TEST_SECRET=supersecret\n' > /run/traefik-runtime.env
        chmod 0600 /run/traefik-runtime.env
      '';
    };
    systemd.services.traefik.after = [ "traefik-runtime-env.service" ];
    systemd.services.traefik.requires = [ "traefik-runtime-env.service" ];
  };

  testScript = ''
    vm.start(allow_reboot=True)
    vm.wait_for_unit("fixture-backend.service")
    vm.wait_for_unit("traefik-runtime-env.service")
    vm.wait_for_unit("traefik.service")
    vm.wait_for_open_port(8000)
    vm.wait_for_open_port(8080)
    vm.fail("curl --fail --silent --max-time 1 http://127.0.0.1:8001/")
    vm.succeed("curl --fail --silent http://127.0.0.1:8080/ping | grep -Fx OK")
    vm.succeed("curl --fail --silent http://127.0.0.1:8000/ | grep -Fx 'Traefik route reached'")
    vm.succeed("curl --fail --silent http://127.0.0.1:8081/dashboard/ | grep -F 'Traefik' >/dev/null")
    vm.succeed("install -d -m 0700 -o traefik -g traefik /var/lib/traefik/acme; printf state > /var/lib/traefik/acme/state; systemctl restart traefik.service; test \"$(cat /var/lib/traefik/acme/state)\" = state")
    vm.succeed("test \"$(stat -c '%U:%G:%a' /var/lib/traefik)\" = traefik:traefik:700")
    vm.succeed("systemctl show traefik.service -p EnvironmentFiles | grep -F /run/traefik-runtime.env")
    vm.succeed("! systemctl cat traefik.service | grep -F supersecret")
    vm.reboot()
    vm.wait_for_unit("traefik.service")
    vm.succeed("test \"$(cat /var/lib/traefik/acme/state)\" = state")
    vm.shutdown()
  '';
}
