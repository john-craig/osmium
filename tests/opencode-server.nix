{ pkgs, lib, module, microvm, opencodeNix }:

let
  mockProvider = pkgs.writeText "osmium-opencode-mock-provider.py" ''
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import json

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/v1/models":
                self.send_error(404)
                return
            body = json.dumps({"object": "list", "data": [{"id": "mock", "object": "model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            if self.path != "/v1/chat/completions" or self.headers.get("Authorization") != "Bearer provider-token":
                self.send_error(401)
                return
            with open("/run/mock-provider-used", "w") as marker:
                marker.write("used")
            request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            completion = {
                "id": "mock-completion",
                "object": "chat.completion",
                "created": 0,
                "model": request.get("model", "mock"),
                "choices": [{"index": 0, "message": {"role": "assistant", "content": "provider-ok"}, "finish_reason": "stop"}],
            }
            if request.get("stream"):
                body = ("data: " + json.dumps({
                    "id": "mock-completion",
                    "object": "chat.completion.chunk",
                    "created": 0,
                    "model": request.get("model", "mock"),
                    "choices": [{"index": 0, "delta": {"role": "assistant", "content": "provider-ok"}, "finish_reason": None}],
                }) + "\n\n" + "data: " + json.dumps({
                    "id": "mock-completion",
                    "object": "chat.completion.chunk",
                    "created": 0,
                    "model": request.get("model", "mock"),
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                }) + "\n\n" + "data: [DONE]\n\n").encode()
                content_type = "text/event-stream"
            else:
                body = json.dumps(completion).encode()
                content_type = "application/json"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
  '';

  base = {
    system.stateVersion = "25.05";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
    nix.settings.trusted-users = [ "root" "opencode" ];
    microvm.guest.enable = false;
    services.osmium.opencodeServer = {
      enable = true;
      credentials = {
        hostDirectory = "/tmp/osmium-opencode-credentials";
        guestDirectory = "/run/opencode/credentials";
      };
      settings = {
        model = "local/mock";
        provider.local = {
          npm = "@ai-sdk/openai-compatible";
          name = "Local mock provider";
          options.baseURL = "http://127.0.0.1:18080/v1";
          models.mock = { name = "Mock"; };
        };
      };
    };
  };
  evaluates = extra: (builtins.tryEval ((lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ microvm.nixosModules.microvm module base extra ];
  }).config.system.build.toplevel)).success;
in
assert evaluates { };
assert !evaluates { services.osmium.opencodeServer.credentials.serverEnvironmentFile = "../password"; };
assert !evaluates { services.osmium.opencodeServer.credentials.providerAuthFile = "subdir/auth.json"; };
assert !evaluates { services.osmium.opencodeServer.listenAddress = "0.0.0.0"; services.osmium.opencodeServer.credentials.serverEnvironmentFile = ""; };
pkgs.testers.runNixOSTest {
  name = "osmium-opencode-server";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default ];
    microvm = {
      hypervisor = "qemu";
      interfaces = [ { type = "user"; id = "opencode-test"; mac = "02:00:00:00:00:11"; } ];
    };
    microvm.guest.enable = false;
    virtualisation.graphics = false;
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; options = [ "mode=755" ]; neededForBoot = true; };
    services.osmium.opencodeServer = {
      enable = true;
      credentials = {
        hostDirectory = "/tmp/shared";
        guestDirectory = "/tmp/shared";
        serverEnvironmentFile = "osmium-opencode-test-server.env";
        providerAuthFile = "osmium-opencode-test-auth.json";
      };
      settings = {
        model = "local/mock";
        provider.local = {
          npm = "@ai-sdk/openai-compatible";
          name = "Local mock provider";
          options.baseURL = "http://127.0.0.1:18080/v1";
          models.mock = { name = "Mock"; };
        };
      };
      workspaces = {
        readonly = {
           hostPath = "/tmp/xchg";
           guestPath = "/tmp/shared";
          readOnly = true;
          proto = "virtiofs";
        };
        writable = {
           hostPath = "/tmp/xchg";
           guestPath = "/tmp/xchg";
          readOnly = false;
          proto = "virtiofs";
        };
      };
    };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
    systemd.services.mock-provider = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python ${mockProvider}";
        Restart = "always";
      };
    };
  };
  testScript = ''
    import os
    from pathlib import Path

    credentials_host = Path(vm.shared_dir)
    workspace_host = credentials_host
    workspace_host.mkdir(parents=True, exist_ok=True)
    workspace_host.chmod(0o755)
    server_env = credentials_host / "osmium-opencode-test-server.env"
    provider_auth = credentials_host / "osmium-opencode-test-auth.json"
    readonly_fixture = workspace_host / "osmium-opencode-test-readonly.txt"
    writable_fixture = workspace_host / "osmium-opencode-test-writable.txt"

    def prepare_shares():
        server_env.write_text("OPENCODE_SERVER_USERNAME=opencode\nOPENCODE_SERVER_PASSWORD=test-password\n")
        provider_auth.write_text('{"local":{"type":"api","key":"provider-token"}}')
        readonly_fixture.write_text("runtime workspace fixture\n")
        writable_fixture.unlink(missing_ok=True)
        for path in (server_env, provider_auth):
            path.chmod(0o444)
        readonly_fixture.chmod(0o644)
        assert server_env.is_file()
        assert provider_auth.is_file()
        assert readonly_fixture.is_file()

    prepare_shares()
    vm.start(allow_reboot=True)

    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_unit("user@1984.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.wait_for_open_port(4096)
    vm.succeed("systemctl is-enabled user@1984.service || true")
    vm.succeed("test \"$(id -u opencode)\" = 1984")
    vm.succeed("test -s /var/lib/opencode/.local/share/osmium-opencode/provider-auth.json")
    vm.succeed("test \"$(systemctl show -p ActiveState --value osmium-opencode-ready.service)\" = active")
    vm.succeed("test -f /tmp/shared/osmium-opencode-test-readonly.txt")
    vm.succeed("touch /tmp/xchg/osmium-opencode-test-writable.txt")
    vm.fail("sh -c 'printf denied > /tmp/shared/osmium-opencode-test-auth.json'")
    assert provider_auth.read_text() == '{"local":{"type":"api","key":"provider-token"}}'
    vm.succeed("curl --fail --user opencode:test-password http://127.0.0.1:4096/global/health")
    vm.fail("curl --fail --user opencode:wrong-password http://127.0.0.1:4096/global/health")
    vm.succeed("curl --fail --user opencode:test-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{}' | jq -r .id > /tmp/opencode-session")
    vm.succeed("test -s /tmp/opencode-session")
    vm.succeed("curl --fail --user opencode:test-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/opencode-session)/message -d '{\"model\":{\"providerID\":\"local\",\"modelID\":\"mock\"},\"parts\":[{\"type\":\"text\",\"text\":\"Reply to this test query\"}]}' -o /tmp/opencode-response")
    vm.wait_for_file("/run/mock-provider-used")
    vm.succeed("grep -F provider-ok /tmp/opencode-response")
    vm.succeed("! grep -R -F test-password /etc/systemd /var/lib/opencode/.config 2>/dev/null")
    vm.succeed("! grep -R -F provider-token /etc/systemd /var/lib/opencode/.config /run/systemd/system 2>/dev/null")
    vm.succeed("test \"$(stat -c %a /var/lib/opencode/.local/share/osmium-opencode/provider-auth.json)\" = 640")
    vm.succeed("cp /var/lib/opencode/.local/share/osmium-opencode/provider-auth.json /var/lib/opencode/.local/share/provider-record-before")
    vm.succeed("printf session-state > /var/lib/opencode/.local/share/opencode/session-marker")
    vm.succeed("printf root-state > /run/impermanent-marker")
    vm.reboot()
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_unit("user@1984.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.succeed("test \"$(cat /var/lib/opencode/.local/share/opencode/session-marker)\" = session-state")
    vm.fail("test -e /run/impermanent-marker")
    vm.succeed("cmp /var/lib/opencode/.local/share/provider-record-before /var/lib/opencode/.local/share/osmium-opencode/provider-auth.json")

    os.chmod(provider_auth, 0o644)
    with open(provider_auth, "w") as f:
        f.write('{"local":{"type":"api","key":"provider-rotated-token"}}')
    os.chmod(provider_auth, 0o444)
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.succeed("grep -F provider-rotated-token /var/lib/opencode/.local/share/opencode/auth.json")
    os.chmod(provider_auth, 0o644)
    with open(provider_auth, "w") as f:
        f.write('{malformed')
    os.chmod(provider_auth, 0o444)
    vm.fail("systemctl start osmium-opencode-reconcile.service")
    vm.succeed("grep -F provider-rotated-token /var/lib/opencode/.local/share/opencode/auth.json")

    os.chmod(provider_auth, 0o644)
    with open(provider_auth, "w") as f:
        f.write('{"local":{"type":"api","key":"provider-rotated-token"}}')
    os.chmod(provider_auth, 0o444)
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.succeed("systemctl --user -M opencode@ start opencode-web.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.wait_for_open_port(4096)

    os.chmod(server_env, 0o644)
    with open(server_env, "w") as f:
        f.write("OPENCODE_SERVER_USERNAME=opencode\nOPENCODE_SERVER_PASSWORD=rotated-password\n")
    os.chmod(server_env, 0o444)
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.wait_for_open_port(4096)
    vm.succeed("for i in $(seq 1 30); do curl --max-time 2 --fail --user opencode:rotated-password http://127.0.0.1:4096/global/health && exit 0; sleep 1; done; exit 1")
    vm.fail("curl --max-time 10 --fail --user opencode:test-password http://127.0.0.1:4096/global/health")
    os.chmod(server_env, 0o644)
    with open(server_env, "w") as f:
        f.write("OPENCODE_SERVER_USERNAME=opencode\n")
    os.chmod(server_env, 0o444)
    vm.fail("systemctl start osmium-opencode-reconcile.service")
    vm.fail("curl --fail --user opencode:rotated-password http://127.0.0.1:4096/global/health")
  '';
}
