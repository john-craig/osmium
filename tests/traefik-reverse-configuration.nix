{ pkgs, module, microvm, mode }:

let
  driftScript = if mode == "drift" then ''
    vm.succeed("cp /run/traefik-dynamic.json /tmp/declared.json")
    vm.succeed("sed -i 's#PathPrefix(`/fixture`)#PathPrefix(`/changed`)#' /run/traefik-dynamic.json")
    vm.succeed("sleep 2; osmium-traefik-observe observe --api-url http://127.0.0.1:8081/api --static-file /run/traefik-static.json --dynamic-file /run/traefik-dynamic.json --output /tmp/after.json")
    vm.succeed("osmium-traefik-observe drift --observation /tmp/after.json --declared /tmp/declared.json --output /tmp/candidate.json")
    vm.succeed("jq -e '.changes | length == 1 and .[0].code == \"dynamic-configuration-drift\"' /tmp/candidate.json")
    vm.succeed("jq -e '.complete == false and (.nix | contains(\"dynamicConfigOptions\"))' /tmp/candidate.json")
  '' else "";
  captureScript = if mode == "live-capture" then ''
    vm.succeed("osmium-traefik-observe capture --api-url http://127.0.0.1:8081/api --static-file /run/traefik-static.json --dynamic-file /run/traefik-dynamic.json --output /tmp/capture.json")
    vm.succeed("jq -e '.capture.provenance.derived_from == \"runtime-observation-and-source-files\" and .capture.complete == false and (.capture.findings | any(.code == \"provider-generated-object\"))' /tmp/capture.json")
    vm.succeed("! grep -F supersecret /tmp/capture.json")
  '' else "";
in
pkgs.testers.runNixOSTest {
  name = "osmium-traefik-${mode}";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "traefik-reverse"; mac = "02:00:00:00:00:42"; } ];
    };

    services.osmium.traefik = {
      enable = true;
      entrypoints.web = { guestPort = 8000; hostPort = 38081; };
      staticConfigOptions = {
        entryPoints.web.address = ":8000";
        providers.file = { filename = "/run/traefik-dynamic.json"; watch = true; };
      };
      dashboard.enable = true;
    };

    systemd.services.traefik-fixture = {
      before = [ "traefik.service" ];
      wantedBy = [ "traefik.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        install -d -m 0755 /run
        cat > /run/traefik-static.json <<'EOF'
        {"entryPoints":{"web":{"address":":8000"}}}
        EOF
        cat > /run/traefik-secret-users <<'EOF'
        operator:supersecret
        EOF
        cat > /run/traefik-dynamic.json <<'EOF'
        {"http":{"routers":{"fixture":{"rule":"PathPrefix(`/fixture`)","entryPoints":["web"],"service":"fixture"}},"services":{"fixture":{"loadBalancer":{"servers":[{"url":"http://127.0.0.1:9000"}]}}},"middlewares":{"secret-auth":{"basicAuth":{"usersFile":"/run/traefik-secret-users"}}}}}
        EOF
      '';
    };
    systemd.services.traefik.after = [ "traefik-fixture.service" ];
    systemd.services.traefik.requires = [ "traefik-fixture.service" ];
    environment.systemPackages = [ pkgs.jq ];
    systemd.services.fixture-backend = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python -m http.server 9000 --directory /var/empty";
        User = "nobody";
      };
    };
  };

  testScript = ''
    vm.start()
    vm.wait_for_unit("traefik.service")
    vm.wait_for_open_port(8081)
    vm.wait_for_open_port(8000)
    vm.succeed("sha256sum /run/traefik-dynamic.json | cut -d ' ' -f1 > /tmp/dynamic.before")
    vm.succeed("osmium-traefik-observe observe --api-url http://127.0.0.1:8081/api --static-file /run/traefik-static.json --dynamic-file /run/traefik-dynamic.json --output /tmp/observation.json")
    vm.succeed("test \"$(sha256sum /run/traefik-dynamic.json | cut -d ' ' -f1)\" = \"$(cat /tmp/dynamic.before)\"")
    vm.succeed("jq -e '.mutation.performed == false and (.runtime.routers | length > 0)' /tmp/observation.json")
    vm.succeed("! grep -F supersecret /tmp/observation.json")
    ${driftScript}
    ${captureScript}
    vm.shutdown()
  '';
}
