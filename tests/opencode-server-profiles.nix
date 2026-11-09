{ pkgs, lib, module, microvm, opencodeNix }:

let
  mcpFixture = ./fixtures/opencode-profile-mcp.py;
  providerFixture = ./fixtures/opencode-profile-provider.py;
  ruleFile = pkgs.writeText "opencode-profile-rule.md" "Immutable rule: profile tool calls must use the declared fixture.\n";
in
pkgs.testers.runNixOSTest {
  name = "osmium-opencode-server-profiles";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default ];
     microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "ocprofiles"; mac = "02:00:00:00:00:14"; } ]; };
    microvm.shares = lib.mkForce [ ];
    microvm.guest.enable = false;
    virtualisation.graphics = false;
    system.stateVersion = "25.05";
    nix.settings.trusted-users = [ "root" "opencode" ];
    services.osmium.opencodeServer = {
      enable = true;
      credentials = {
        hostDirectory = "/tmp/shared";
        guestDirectory = "/run/opencode/credentials";
        serverEnvironmentFile = "server.env";
        providerAuthFile = "auth.json";
      };
      settings = {
        model = "local/mock";
        provider.local = {
          npm = "@ai-sdk/openai-compatible";
          name = "Profile fixture provider";
          options.baseURL = "http://127.0.0.1:18080/v1";
          models.mock = { name = "Mock"; };
        };
      };
      mcpServers = {
        facts = {
          type = "local";
          command = [ "${pkgs.python3}/bin/python" "${mcpFixture}" "facts" "/tmp/opencode-facts-called" ];
          environment.MCP_TOKEN = "{env:MCP_TOKEN}";
        };
        audit = {
          type = "local";
          command = [ "${pkgs.python3}/bin/python" "${mcpFixture}" "audit" "/tmp/opencode-audit-called" ];
          environment.MCP_TOKEN = "{env:MCP_TOKEN}";
        };
      };
      skills = {
        facts = { path = pkgs.writeTextDir "facts/SKILL.md" "Facts skill\n"; };
        audit = { path = pkgs.writeTextDir "audit/SKILL.md" "Audit skill\n"; };
      };
      profiles = {
        facts = { model = "local/mock"; rules = [ "Selected profile: facts" ]; ruleFiles = [ ruleFile ]; skills = [ "facts" ]; mcpServers = [ "facts" ]; };
        audit = { model = "local/mock"; rules = [ "Selected profile: audit" ]; skills = [ "audit" ]; mcpServers = [ "audit" ]; };
        disabled = { enable = false; model = "local/mock"; };
      };
      reverseConfiguration.enable = true;
    };
    systemd.services.mock-provider = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { ExecStart = "${pkgs.python3}/bin/python ${providerFixture}"; Restart = "always"; };
    };
     systemd.services.osmium-opencode-reconcile.wantedBy = lib.mkForce [ ];
     systemd.services.osmium-opencode-ready.wantedBy = lib.mkForce [ ];
     systemd.paths.osmium-opencode-reconcile.wantedBy = lib.mkForce [ ];
     systemd.timers.osmium-opencode-reconcile.wantedBy = lib.mkForce [ ];
    systemd.services.linger-users.requires = lib.mkForce [ ];
    systemd.services.linger-users.after = lib.mkForce [ ];
     systemd.user.services.opencode-web.enable = false;
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.python3 ];
  };
  testScript = ''
    vm.start(allow_reboot=True)
    vm.succeed("mkdir -p /run/opencode/credentials")
    vm.succeed("printf 'OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=profile-password\\nMCP_TOKEN=profile-token\\n' > /run/opencode/credentials/server.env")
    vm.succeed("printf '{\"local\":{\"type\":\"api\",\"key\":\"provider-token\"}}' > /run/opencode/credentials/auth.json")
    vm.succeed("chmod 0444 /run/opencode/credentials/server.env /run/opencode/credentials/auth.json")
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.wait_for_unit("user@1984.service")
    vm.succeed("systemctl start osmium-opencode-ready.service")
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.wait_for_open_port(4096)
    auth_args = "--user opencode:profile-password"
    vm.succeed("curl --fail --max-time 30 %s http://127.0.0.1:4096/global/health" % auth_args)
    vm.succeed("curl --fail --max-time 30 %s -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{}' | jq -r .id > /tmp/facts-session" % auth_args)
    vm.succeed("curl --fail --max-time 30 %s -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/facts-session)/message -d '{\"agent\":\"facts\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}' -o /tmp/facts-response" % auth_args)
    print("=== facts response ===")
    print(vm.succeed("cat /tmp/facts-response"))
    print("=== provider summary transcript ===")
    print(vm.succeed("cat /tmp/opencode-profile-provider-summary.jsonl"))
    print("=== MCP wire transcript ===")
    print(vm.succeed("cat /tmp/opencode-facts-called.wire"))
    print("=== OpenCode service log ===")
    print(vm.succeed("journalctl -u opencode-web.service --no-pager -n 200"))
    print("=== OpenCode user service log ===")
    print(vm.succeed("XDG_RUNTIME_DIR=/run/user/1984 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1984/bus journalctl --user -u opencode-web.service --no-pager -n 200"))
    vm.succeed("test -s /tmp/opencode-profile-provider-transcript.jsonl")
    vm.succeed("grep -F 'facts_lookup' /tmp/opencode-profile-provider-transcript.jsonl")
    vm.succeed("test -s /tmp/opencode-facts-called.transcript")
    vm.succeed("grep -F 'tools/call' /tmp/opencode-facts-called.transcript")
    vm.succeed("grep -F '\"key\": \"profile\"' /tmp/opencode-facts-called.transcript")
    vm.wait_for_file("/tmp/opencode-facts-called", timeout=30)
    vm.succeed("grep -F profile-mcp-ok /tmp/facts-response")
    vm.succeed("test ! -e /tmp/opencode-audit-called")
    vm.succeed("jq -e '.agent.facts.mode == \"primary\" and ((.agent.facts.prompt | index(\"Selected profile: facts\")) < (.agent.facts.prompt | index(\"Immutable rule:\"))) and (.skills.paths | length == 2) and (.mcp.facts.environment.MCP_TOKEN == \"{env:MCP_TOKEN}\") and (.agent.facts.permission.skill.facts == \"allow\") and (.agent.facts.permission.skill.audit == \"deny\") and (.agent.facts.permission.\"audit_*\" == \"deny\") and (.agent.audit.permission.skill.facts == \"deny\") and (.agent.audit.permission.\"facts_*\" == \"deny\")' /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("grep -F 'facts_lookup' /tmp/opencode-profile-provider-transcript.jsonl")
    vm.succeed("grep -F 'facts-value' /tmp/opencode-profile-provider-transcript.jsonl")

    vm.succeed("curl --fail --max-time 30 %s -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{}' | jq -r .id > /tmp/audit-session" % auth_args)
    vm.succeed("curl --fail --max-time 30 %s -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/audit-session)/message -d '{\"agent\":\"audit\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}' -o /tmp/audit-response" % auth_args)
    vm.wait_for_file("/tmp/opencode-audit-called")
    vm.succeed("grep -F profile-mcp-ok /tmp/audit-response")
    vm.succeed("grep -F 'audit_lookup' /tmp/opencode-profile-provider-transcript.jsonl")
    vm.succeed("test $(wc -l < /tmp/opencode-facts-called) = 1")
    vm.succeed("test $(wc -l < /tmp/opencode-audit-called) = 1")
    vm.fail("curl --max-time 10 --fail --user opencode:profile-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/audit-session)/message -d '{\"agent\":\"unknown\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}'")
    vm.fail("curl --max-time 10 --fail --user opencode:profile-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/audit-session)/message -d '{\"agent\":\"disabled\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}'")

    vm.succeed("jq 'del(.agent.audit)' /var/lib/opencode/.config/opencode/opencode.json > /tmp/opencode.json && mv /tmp/opencode.json /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("systemctl --user -M opencode@ restart opencode-web.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.succeed("for i in $(seq 1 30); do curl --max-time 2 --fail --user opencode:profile-password http://127.0.0.1:4096/global/health && exit 0; sleep 1; done; exit 1")
    vm.fail("curl --max-time 10 --fail --user opencode:profile-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{}' | jq -r .id > /tmp/removed-session && curl --max-time 10 --fail --user opencode:profile-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/removed-session)/message -d '{\"agent\":\"audit\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}'")
    vm.fail("curl --max-time 10 --fail --user opencode:profile-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/audit-session)/message -d '{\"agent\":\"audit\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}'")

    vm.succeed("chmod 0644 /run/opencode/credentials/server.env")
    vm.succeed("printf 'OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=profile-password-rotated\\nMCP_TOKEN=profile-token-rotated\\n' > /run/opencode/credentials/server.env")
    vm.succeed("chmod 0444 /run/opencode/credentials/server.env")
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.wait_for_unit("opencode-web.service", user="opencode")
    vm.succeed("for i in $(seq 1 30); do curl --max-time 2 --fail --user opencode:profile-password-rotated http://127.0.0.1:4096/global/health && exit 0; sleep 1; done; exit 1")
    vm.fail("curl --max-time 5 --fail --user opencode:profile-password http://127.0.0.1:4096/global/health")
    vm.succeed("curl --fail --max-time 30 --user opencode:profile-password-rotated -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{}' | jq -r .id > /tmp/rotated-session")
    vm.succeed("curl --fail --max-time 30 --user opencode:profile-password-rotated -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/rotated-session)/message -d '{\"agent\":\"facts\",\"parts\":[{\"type\":\"text\",\"text\":\"Use the profile fixture\"}]}' -o /tmp/rotated-response")
    vm.succeed("grep -F profile-mcp-ok /tmp/rotated-response")
    vm.succeed("test $(wc -l < /tmp/opencode-facts-called) = 2")
    vm.succeed("MCP_TOKEN=profile-token printf '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"facts_lookup\",\"arguments\":{\"key\":\"profile\"}}}\n' | env MCP_TOKEN=old-token ${pkgs.python3}/bin/python ${mcpFixture} facts /tmp/opencode-old-token-called | jq -e '.error.code == -32001'")
    vm.succeed("test ! -e /tmp/opencode-old-token-called")
    vm.succeed("matches=$(grep -R -F profile-token /var/lib/opencode/.config /var/lib/opencode/.local/share 2>/dev/null | grep -v profile-token-rotated || true); test -z \"$matches\" || { printf '%s\\n' \"$matches\"; exit 1; }")
    vm.succeed("! ps -eo args | grep -E 'profile-(token|password)'")
    vm.succeed("! journalctl --no-pager | grep -F -e profile-token -e profile-password")
    vm.succeed("! grep -R -F -e profile-token -e profile-password /tmp/opencode-profile-provider-transcript.jsonl /tmp/opencode-profile-provider-summary.jsonl /tmp/opencode-profile-provider-wire.jsonl")
    vm.succeed("osmium-opencode-observe > /tmp/rotated-observe.json && osmium-opencode-drift > /tmp/rotated-drift.json")
    vm.succeed("! grep -R -F -e profile-token -e profile-password /tmp/rotated-observe.json /tmp/rotated-drift.json")
  '';
}
