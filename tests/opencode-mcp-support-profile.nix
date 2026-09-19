{ pkgs, lib, module, microvm, opencodeNix, opencodeMcp, diagnosticOnly ? false, reverseMode ? null }:

let
  mcpClient = pkgs.writeScriptBin "osmium-opencode-mcp-client" (builtins.readFile ./fixtures/opencode-mcp-client.py);
  profileProvider = pkgs.writeScriptBin "opencode-profile-provider" (builtins.readFile ./fixtures/opencode-profile-provider.py);
  attachPty = pkgs.writeScriptBin "osmium-opencode-attach-pty" (builtins.readFile ./fixtures/opencode-attach-pty.py);
  targetConfig = pkgs.writeText "opencode-target.json" (builtins.toJSON {
    model = "local/mock";
    provider.local = {
      npm = "@ai-sdk/openai-compatible";
      name = "Support fixture provider";
      options.baseURL = "http://127.0.0.1:18080/v1";
      models.mock = { name = "Mock"; };
    };
  });
  targetXdgOpen = pkgs.writeShellScriptBin "xdg-open" "exit 0";
  targetServer = pkgs.writeShellScript "opencode-target-server" ''
    set -eu
    export PATH=${lib.makeBinPath [ targetXdgOpen ]}:$PATH
    install -d -m 0750 -o opencode -g opencode /var/lib/opencode-target/.config/opencode
    install -o opencode -g opencode -m 0600 ${targetConfig} /var/lib/opencode-target/.config/opencode/opencode.json
    exec ${pkgs.opencode}/bin/opencode web --hostname 127.0.0.1 --port 4097
  '';
  base = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default (final: _prev: { opencode-mcp = opencodeMcp; }) ];
    microvm.guest.enable = false;
    virtualisation.graphics = false;
    virtualisation.memorySize = 4096;
    system.stateVersion = "25.05";
    nix.settings.trusted-users = [ "root" "opencode" ];
    systemd.tmpfiles.rules = [
      "d /run/opencode/credentials 0755 root root -"
      "f /run/opencode/credentials/server.env 0444 root root - OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=support-password"
      "f /run/opencode/credentials/auth.json 0444 root root - {\\\"local\\\":{\\\"type\\\":\\\"api\\\",\\\"key\\\":\\\"provider-token\\\"}}"
      "d /var/lib/opencode-target 0750 opencode opencode -"
    ];
    services.osmium.opencodeServer = {
      enable = true;
      credentials = { hostDirectory = "/run/opencode/credentials"; serverEnvironmentFile = "server.env"; providerAuthFile = "auth.json"; };
      settings = {
        model = "local/mock";
         provider.local = { npm = "@ai-sdk/openai-compatible"; name = "Support fixture provider"; options.baseURL = "http://127.0.0.1:18080/v1"; models.mock = { name = "Mock"; }; };
      };
       supportProfile = { enable = true; model = "local/mock"; package = opencodeMcp; };
      profiles.ordinary = { model = "local/mock"; rules = [ "ordinary-profile-marker" ]; };
      reverseConfiguration.enable = true;
    };
    systemd.services.home-manager-opencode.requires = lib.mkForce [ ];
    systemd.services.home-manager-opencode.after = lib.mkForce [ ];
    systemd.services.mock-provider = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { ExecStart = "${pkgs.python3}/bin/python ${profileProvider}/bin/opencode-profile-provider"; Restart = "always"; };
    };
    systemd.services.opencode-target = {
      wantedBy = [ "multi-user.target" ];
      after = [ "osmium-opencode-reconcile.service" ];
      serviceConfig = {
        User = "opencode";
        Group = "opencode";
         Environment = [ "HOME=/var/lib/opencode-target" "XDG_RUNTIME_DIR=/run/opencode-target" "OPENCODE_SERVER_USERNAME=opencode" "OPENCODE_SERVER_PASSWORD=support-password" "OPENCODE_LOG_LEVEL=debug" ];
        RuntimeDirectory = "opencode-target";
        ExecStart = targetServer;
        Restart = "always";
      };
    };
     environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.python3 pkgs.util-linux opencodeMcp mcpClient attachPty ];
  };
in
pkgs.testers.runNixOSTest {
  name = if diagnosticOnly then "osmium-opencode-mcp-support-profile-diagnostic" else if reverseMode == "drift" then "osmium-opencode-mcp-support-profile-drift-reverse-configuration" else if reverseMode == "live-capture" then "osmium-opencode-mcp-support-profile-live-capture-reverse-configuration" else "osmium-opencode-mcp-support-profile";
  nodes = { vm = base; } // lib.optionalAttrs (reverseMode != null) { vm2 = base; };
  testScript = if reverseMode == "drift" then ''
    import json
    vm.start()
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.wait_for_unit("opencode-target.service")
    vm.wait_for_open_port(4097)
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.wait_for_unit("user@1984.service")
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_open_port(4096)
    vm.succeed("find /var/lib/opencode/.local/share -type f -print0 | sort -z | xargs -0 sha256sum > /tmp/drift-state-before; sha256sum /run/opencode/credentials/server.env /run/opencode/credentials/auth.json > /tmp/drift-credentials-before")
    vm.succeed("cp /var/lib/opencode/.config/opencode/opencode.json /tmp/original-opencode.json")
    vm.succeed("jq '.agent.\"osmium-support\".model = \"local/drifted\" | .mcp.\"opencode-support\".environment.OPENCODE_TOOL_PROFILE = \"essential\"' /tmp/original-opencode.json > /tmp/drifted-opencode.json && install -o opencode -g opencode -m 0600 /tmp/drifted-opencode.json /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("osmium-opencode-drift > /tmp/support-drift.json")
    vm.succeed("jq -e '.drift == true and .supportProfile.model == \"local/drifted\" and .supportProfile.toolProfile == \"essential\" and .candidate.completeness.complete == false and .candidate.completeness.activation_ready == false and .candidate.provenance.review_only == true and (.candidate.provenance.source_fields | index(\"supportProfile\")) != null and (.candidate.findings | map(.code) | index(\"support-package-source-unresolved\")) != null and (.candidate.findings | map(.code) | index(\"secret-excluded\")) != null' /tmp/support-drift.json")
    vm.succeed("! grep -E -i 'support-password|provider-token' /tmp/support-drift.json")
    vm.succeed("cmp /tmp/drifted-opencode.json /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("find /var/lib/opencode/.local/share -type f -print0 | sort -z | xargs -0 sha256sum > /tmp/drift-state-after; sha256sum /run/opencode/credentials/server.env /run/opencode/credentials/auth.json > /tmp/drift-credentials-after; cmp /tmp/drift-state-before /tmp/drift-state-after && cmp /tmp/drift-credentials-before /tmp/drift-credentials-after")
    candidate = json.loads(vm.succeed("cat /tmp/support-drift.json"))["candidate"]["services"]["osmium"]["opencodeServer"]
    vm2.start()
    vm2.succeed("systemctl start osmium-opencode-reconcile.service")
    vm2.wait_for_unit("opencode-target.service")
    vm2.wait_for_open_port(4097)
    vm2.succeed("systemctl start home-manager-opencode.service")
    vm2.wait_for_unit("user@1984.service")
    vm2.wait_for_unit("osmium-opencode-ready.service")
    vm2.wait_for_open_port(4096)
    vm2.succeed("env OPENCODE_BASE_URL=%s OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password OPENCODE_TOOL_PROFILE=%s osmium-opencode-mcp-client %s/bin/opencode-mcp --output /tmp/drift-replayed.json --call 'opencode_status={}'" % (candidate["supportProfile"]["endpoint"], candidate["supportProfile"]["toolProfile"], "${opencodeMcp}"))
    vm2.succeed("jq -e '.calls[0].result.isError // false | not' /tmp/drift-replayed.json")
    vm2.succeed("curl --fail --user opencode:support-password -X POST http://127.0.0.1:4096/session -d '{\"title\":\"drift-replayed\"}' | jq -r .id > /tmp/replayed-session")
    vm2.succeed("test -s /tmp/replayed-session")
   '' else if reverseMode == "live-capture" then ''
    import json
    vm.start()
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.wait_for_unit("opencode-target.service")
    vm.wait_for_open_port(4097)
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.wait_for_unit("user@1984.service")
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_open_port(4096)
    vm.succeed("curl --fail --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{\"title\":\"captured-support\"}' | jq -r .id > /tmp/captured-session")
    vm.succeed("env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password osmium-opencode-mcp-client ${opencodeMcp}/bin/opencode-mcp --output /tmp/captured-workflow.json --call 'opencode_session_list={}' --call 'opencode_message_send={\"sessionId\":\"'$(cat /tmp/captured-session)'\",\"text\":\"capture-runtime-marker\",\"agent\":\"ordinary\"}'")
    vm.succeed("jq -e '(.calls | map(.name) | index(\"opencode_session_list\")) and (.calls[1].result.isError // false | not)' /tmp/captured-workflow.json")
    vm.succeed("find /var/lib/opencode/.local/share -type f ! -path '*/opencode/log/*' ! -name '*-shm' ! -name '*-wal' -print0 | sort -z | xargs -0 sha256sum > /tmp/capture-state-before")
    vm.succeed("osmium-opencode-observe > /tmp/support-capture.json")
    vm.succeed("osmium-opencode-observe > /tmp/support-capture-repeat.json && cmp /tmp/support-capture.json /tmp/support-capture-repeat.json")
    vm.succeed("jq -e '.schema_version == 3 and .source.origin == \"observed\" and .source.method == \"config-readiness\" and .supportProfile.enabled == true and .supportProfile.name == \"osmium-support\" and .supportProfile.mcpName == \"opencode-support\" and .supportProfile.endpoint == \"http://127.0.0.1:4096\" and .supportProfile.readiness == \"healthy\" and .supportProfile.mcpProtocol == \"healthy\" and .sessions.unresolved == true and .credentials.secrets.excluded == true and .complete == false and .activation_ready == false' /tmp/support-capture.json")
    vm.succeed("! grep -E -i 'support-password|provider-token' /tmp/support-capture.json")
    vm.succeed("find /var/lib/opencode/.local/share -type f ! -path '*/opencode/log/*' ! -name '*-shm' ! -name '*-wal' -print0 | sort -z | xargs -0 sha256sum > /tmp/capture-state-after; cmp /tmp/capture-state-before /tmp/capture-state-after || { diff -u /tmp/capture-state-before /tmp/capture-state-after; exit 1; }")
    capture = json.loads(vm.succeed("cat /tmp/support-capture.json"))
    vm2.start()
    vm2.succeed("systemctl start osmium-opencode-reconcile.service")
    vm2.wait_for_unit("opencode-target.service")
    vm2.wait_for_open_port(4097)
    vm2.succeed("systemctl start home-manager-opencode.service")
    vm2.wait_for_unit("user@1984.service")
    vm2.wait_for_unit("osmium-opencode-ready.service")
    vm2.wait_for_open_port(4096)
    vm2.succeed("env OPENCODE_BASE_URL=%s OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password OPENCODE_TOOL_PROFILE=%s osmium-opencode-mcp-client %s/bin/opencode-mcp --output /tmp/capture-replayed.json --call 'opencode_status={}'" % (capture["supportProfile"]["runtimeEndpoint"], capture["supportProfile"]["runtimeToolProfile"], "${opencodeMcp}"))
    vm2.succeed("jq -e '.calls[0].result.isError // false | not' /tmp/capture-replayed.json")
  '' else if diagnosticOnly then ''
    vm.start()
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.wait_for_unit("opencode-target.service")
    vm.wait_for_open_port(4097)
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.wait_for_unit("user@1984.service")
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_open_port(4096)
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{\"title\":\"diagnostic-support-session\"}' | jq -r .id > /tmp/diagnostic-session")
    status, response = vm.execute("curl --max-time 45 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/diagnostic-session)/message -d '{\"agent\":\"osmium-support\",\"parts\":[{\"type\":\"text\",\"text\":\"MCP_CALL opencode-support_opencode_status\\nMCP_ARGS {}\"}]}'")
    print("support-request-exit=%s" % status)
    print(response)
    print(vm.succeed("cat /run/osmium-opencode/support-mcp.log 2>/dev/null || true"))
    print(vm.succeed("journalctl --no-pager -u opencode-target.service"))
    print(vm.succeed("journalctl --no-pager -u user@1984.service"))
    print(vm.succeed("journalctl --no-pager _SYSTEMD_USER_UNIT=opencode-web.service"))
    print(vm.succeed("for file in /tmp/opencode-profile-provider-wire.jsonl /tmp/opencode-profile-provider-transcript.jsonl; do test -e \"$file\" && cat \"$file\" || true; done"))
    assert status == 0, "support MCP request failed"
  '' else ''
    vm.start()
    vm.succeed("systemctl start osmium-opencode-reconcile.service")
    vm.wait_for_unit("opencode-target.service")
    vm.wait_for_open_port(4097)
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.wait_for_unit("user@1984.service")
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_open_port(4096)
    vm.succeed("test -s /var/lib/opencode/.local/share/osmium-opencode/support-readiness.json")
    vm.succeed("jq -e '.status == \"healthy\" and .support_profile == \"enabled\"' /var/lib/opencode/.local/share/osmium-opencode/support-readiness.json")
    vm.succeed("jq -e '.mcp.\"opencode-support\".command[0] | endswith(\"/bin/osmium-opencode-support-mcp\")' /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("jq -e '.mcp.\"opencode-support\".environment.OPENCODE_AUTO_SERVE == \"false\" and .mcp.\"opencode-support\".environment.OPENCODE_SERVER_PASSWORD == \"{env:OPENCODE_SERVER_PASSWORD}\"' /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("test -r /run/osmium-opencode/support-server.env && ! grep -F support-password /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("launcher=$(jq -r '.mcp.\"opencode-support\".command[0]' /var/lib/opencode/.config/opencode/opencode.json); env -u OPENCODE_SERVER_PASSWORD osmium-opencode-mcp-client \"$launcher\" --output /tmp/support-launcher.json --call 'opencode_status={}'")
    vm.succeed("jq -e '.calls[0].name == \"opencode_status\" and (.calls[0].result.isError // false | not)' /tmp/support-launcher.json")
    vm.succeed("env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password osmium-opencode-mcp-client ${opencodeMcp}/bin/opencode-mcp --output /tmp/mcp-client.json --call 'opencode_setup={}' --call 'opencode_status={}'")
    vm.succeed("jq -e '(.tools.tools | map(.name) | index(\"opencode_setup\")) and (.tools.tools | map(.name) | index(\"opencode_session_list\")) and (.tools.tools | map(.name) | index(\"opencode_session_get\")) and (.tools.tools | map(.name) | index(\"opencode_session_create\")) and (.tools.tools | map(.name) | index(\"opencode_run\")) and (.tools.tools | map(.name) | index(\"opencode_message_send\")) and (.tools.tools | map(.name) | index(\"opencode_wait\")) and (.tools.tools | map(.name) | index(\"opencode_conversation\"))' /tmp/mcp-client.json")
    vm.succeed("jq -e '(.calls | map(.name) | index(\"opencode_setup\")) and (.calls | map(.name) | index(\"opencode_status\")) and (.calls[].result.isError // false | not)' /tmp/mcp-client.json")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{\"title\":\"api-support-session\"}' | jq -r .id > /tmp/api-session")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{\"title\":\"mcp-support-session\"}' | jq -r .id > /tmp/mcp-session")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session -d '{\"title\":\"api-ordinary-session\"}' | jq -r .id > /tmp/ordinary-session")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/api-session)/message -d '{\"agent\":\"ordinary\",\"parts\":[{\"type\":\"text\",\"text\":\"api-session-marker\"}]}' -o /tmp/api-response && grep -F agent-dispatch-ok /tmp/api-response")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/ordinary-session)/message -d '{\"agent\":\"ordinary\",\"parts\":[{\"type\":\"text\",\"text\":\"plain dispatch control\"}]}' | tee /tmp/ordinary-response | grep -F agent-dispatch-ok")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/ordinary-session)/message -d '{\"agent\":\"ordinary\",\"parts\":[{\"type\":\"text\",\"text\":\"MCP_CALL opencode-support_opencode_status MCP_ARGS {}\"}]}' -o /tmp/ordinary-support-response && ! grep -F mcp-result-ok /tmp/ordinary-support-response")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/api-session)/message -d '{\"agent\":\"osmium-support\",\"parts\":[{\"type\":\"text\",\"text\":\"plain support dispatch control\"}]}' | tee /tmp/support-plain-response | grep -F agent-dispatch-ok")
    vm.succeed("status=$(curl --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/mcp-session)/message -d '{\"agent\":\"osmium-support\",\"parts\":[{\"type\":\"text\",\"text\":\"MCP_CALL opencode-support_opencode_status MCP_ARGS {}\"}]}' -o /tmp/support-response -w '%{http_code}'); if [ \"$status\" != 200 ]; then cat /tmp/support-response; cat /run/osmium-opencode/support-mcp.log 2>/dev/null || true; for file in /tmp/opencode-profile-provider-wire.jsonl /tmp/opencode-profile-provider-transcript.jsonl; do test -e \"$file\" && cat \"$file\" || true; done; journalctl --no-pager -u opencode-target.service; journalctl --no-pager -u user@1984.service; exit 1; fi")
    vm.succeed("grep -F mcp-result-ok /tmp/support-response")
    vm.succeed("grep -F opencode-support_opencode_status /tmp/opencode-profile-provider-transcript.jsonl")
    vm.succeed("launcher=$(jq -r '.mcp.\"opencode-support\".command[0]' /var/lib/opencode/.config/opencode/opencode.json); env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password osmium-opencode-mcp-client \"$launcher\" --output /tmp/support-rejection.json --call 'opencode_message_send={\"sessionId\":\"'$(cat /tmp/api-session)'\",\"text\":\"unknown profile marker\",\"agent\":\"unknown\"}'")
    vm.succeed("jq -e '.calls[0].result.isError == true' /tmp/support-rejection.json")
    vm.succeed("launcher=$(jq -r '.mcp.\"opencode-support\".command[0]' /var/lib/opencode/.config/opencode/opencode.json); env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password osmium-opencode-mcp-client \"$launcher\" --output /tmp/support-message.json --call 'opencode_message_send={\"sessionId\":\"'$(cat /tmp/api-session)'\",\"text\":\"mcp-session-marker\",\"agent\":\"ordinary\"}'")
    vm.succeed("jq -e '.calls[0].result.isError // false | not' /tmp/support-message.json")
    vm.succeed("curl --fail --max-time 30 --user opencode:support-password -H 'Content-Type: application/json' -X POST http://127.0.0.1:4096/session/$(cat /tmp/api-session)/message -d '{\"agent\":\"ordinary\",\"parts\":[{\"type\":\"text\",\"text\":\"api-continuation-marker\"}]}' | grep -F agent-dispatch-ok")
    vm.succeed("launcher=$(jq -r '.mcp.\"opencode-support\".command[0]' /var/lib/opencode/.config/opencode/opencode.json); env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password osmium-opencode-mcp-client \"$launcher\" --output /tmp/support-ordered.json --call 'opencode_conversation={\"sessionId\":\"'$(cat /tmp/api-session)'\"}'")
    vm.succeed("jq -e '((.calls[0].result | tostring) | contains(\"api-session-marker\")) and ((.calls[0].result | tostring) | contains(\"mcp-session-marker\")) and ((.calls[0].result | tostring) | contains(\"api-continuation-marker\"))' /tmp/support-ordered.json")
    vm.succeed("OPENCODE_BIN=${pkgs.opencode}/bin/opencode OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password OPENCODE_ATTACH_MARKER=terminal-session-marker OPENCODE_ATTACH_OUTPUT=/tmp/opencode-attach-pty.log osmium-opencode-attach-pty > /tmp/attach-session")
    vm.succeed("test -s /tmp/opencode-attach-pty.log.session")
    vm.succeed("attach_session=$(cat /tmp/opencode-attach-pty.log.session); curl --fail --max-time 30 --user opencode:support-password http://127.0.0.1:4096/session/$attach_session/message | grep -F terminal-session-marker")
    vm.succeed("env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password osmium-opencode-mcp-client ${opencodeMcp}/bin/opencode-mcp --output /tmp/mcp-sessions.json --call 'opencode_session_list={}' --call 'opencode_session_get={\"id\":\"'$(cat /tmp/api-session)'\"}' --call 'opencode_conversation={\"sessionId\":\"'$(cat /tmp/api-session)'\"}' --call 'opencode_session_get={\"id\":\"'$(cat /tmp/opencode-attach-pty.log.session)'\"}' --call 'opencode_conversation={\"sessionId\":\"'$(cat /tmp/opencode-attach-pty.log.session)'\"}'")
    vm.succeed("jq -e '(.calls | map(.name) | index(\"opencode_session_list\")) and ((.calls | map(select(.name == \"opencode_conversation\") | .result) | tostring) | contains(\"api-session-marker\")) and ((.calls | map(select(.name == \"opencode_conversation\") | .result) | tostring) | contains(\"terminal-session-marker\"))' /tmp/mcp-sessions.json")
    vm.succeed("osmium-opencode-observe > /tmp/support-observe.json && osmium-opencode-drift > /tmp/support-drift.json")
    vm.succeed("jq -e '.supportProfile.enabled == true and .supportProfile.name == \"osmium-support\" and .supportProfile.mcpName == \"opencode-support\"' /tmp/support-observe.json")
    vm.succeed("jq -e '.candidate.complete == false and (.candidate.findings | map(.code) | index(\"profile-source-unresolved\")) != null' /tmp/support-drift.json")
    vm.succeed("! grep -R -F support-password /tmp/support-observe.json /tmp/support-drift.json /var/lib/opencode/.config/opencode/opencode.json")
    vm.succeed("chmod 0644 /run/opencode/credentials/server.env")
    vm.succeed("printf 'OPENCODE_SERVER_USERNAME=opencode\\nOPENCODE_SERVER_PASSWORD=support-password-rotated\\n' > /run/opencode/credentials/server.env")
    vm.succeed("chmod 0444 /run/opencode/credentials/server.env && systemctl start osmium-opencode-reconcile.service")
    vm.succeed("for i in $(seq 1 30); do curl --max-time 2 --fail --user opencode:support-password-rotated http://127.0.0.1:4096/global/health && exit 0; sleep 1; done; exit 1")
    vm.fail("curl --max-time 5 --fail --user opencode:support-password http://127.0.0.1:4096/global/health")
    vm.succeed("launcher=$(jq -r '.mcp.\"opencode-support\".command[0]' /var/lib/opencode/.config/opencode/opencode.json); env OPENCODE_BASE_URL=http://127.0.0.1:4096 OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD=support-password-rotated osmium-opencode-mcp-client \"$launcher\" --output /tmp/rotated-support.json --call 'opencode_status={}'")
    vm.succeed("jq -e '.calls[0].result.isError // false | not' /tmp/rotated-support.json")
    vm.succeed("! grep -R -F -e support-password -e provider-token /tmp/support-observe.json /tmp/support-drift.json /var/lib/opencode/.config/opencode /var/lib/opencode/.local/share/osmium-opencode 2>/dev/null")
  '';
}
