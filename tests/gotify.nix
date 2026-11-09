{ pkgs, module, microvm, mode ? "service" }:

let
  adminPassword = "gotify-admin-password";
  userPassword = "gotify-user-password";
  externalPassword = "gotify-external-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-gotify-${mode}";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "gotifyvm"; mac = "02:00:00:00:00:31"; } ];
    };
    services.osmium.gotify = {
      enable = true;
      hostHttpPort = 38100;
      admin = { enable = true; username = "gotify-admin"; passwordFile = "/etc/gotify-admin-password"; };
      users.alerts = { username = "alerts"; passwordFile = "/etc/gotify-user-password"; };
      applications.alerts = {
        owner = "alerts";
        name = "alerts-client";
        description = "Declarative alerts client";
        output = { secretPath = "/var/lib/gotify/credentials/alerts.token"; owner = "gotify"; group = "gotify"; mode = "0400"; };
      };
    };
    environment.etc."gotify-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "gotify"; group = "gotify"; };
    environment.etc."gotify-user-password" = { text = "${userPassword}\n"; mode = "0400"; user = "gotify"; group = "gotify"; };
    environment.etc."gotify-external-password" = { text = "${externalPassword}\n"; mode = "0400"; user = "gotify"; group = "gotify"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("gotify-server.service")
    vm.succeed("systemctl start osmium-gotify-admin-bootstrap.service")
    vm.succeed("systemctl start osmium-gotify-reconcile.service")
    ${if mode == "service" then ''
      vm.succeed("test -s /var/lib/gotify/credentials/alerts.token")
      vm.succeed("curl --fail --silent -H 'Content-Type: application/json' -X POST http://127.0.0.1:8080/message?token=$(cat /var/lib/gotify/credentials/alerts.token) -d '{\"message\":\"hello\",\"title\":\"test\"}'")
      vm.succeed("curl --fail --silent -u alerts:gotify-user-password http://127.0.0.1:8080/application/1/message > /tmp/messages.json; jq -e '.messages | length >= 1' /tmp/messages.json")
      vm.succeed("test \"$(stat -c '%U:%G:%a' /var/lib/gotify/credentials/alerts.token)\" = gotify:gotify:400")
      vm.succeed("test -s /var/lib/gotify/.osmium-ledger.json && ! grep -E -i '${adminPassword}|${userPassword}' /var/lib/gotify/.osmium-ledger.json")
      vm.succeed("token_before=$(cat /var/lib/gotify/credentials/alerts.token); systemctl restart osmium-gotify-reconcile.service; test \"$(cat /var/lib/gotify/credentials/alerts.token)\" = \"$token_before\"")
      vm.succeed("cp /var/lib/gotify/credentials/alerts.token /tmp/alerts.token")
      vm.succeed("rm /var/lib/gotify/credentials/alerts.token")
      vm.fail("systemctl restart osmium-gotify-reconcile.service")
      vm.succeed("install -o gotify -g gotify -m 0400 /tmp/alerts.token /var/lib/gotify/credentials/alerts.token")
      vm.succeed("systemctl restart osmium-gotify-reconcile.service")
      vm.succeed("test -s /var/lib/gotify/credentials/alerts.token")
      vm.succeed("printf 'gotify-user-password-rotated\\n' > /etc/gotify-user-password")
      vm.succeed("systemctl restart osmium-gotify-reconcile.service")
      vm.fail("curl --fail --silent -u alerts:${userPassword} http://127.0.0.1:8080/application/1/message")
      vm.succeed("curl --fail --silent -u alerts:gotify-user-password-rotated http://127.0.0.1:8080/application/1/message")
    '' else if mode == "drift-reverse-configuration" then ''
      vm.succeed("ledger_before=$(sha256sum /var/lib/gotify/.osmium-ledger.json | cut -d' ' -f1); curl --fail --silent -u alerts:gotify-user-password -H 'Content-Type: application/json' -X PUT http://127.0.0.1:8080/application/1 -d '{\"name\":\"alerts-client\",\"description\":\"Runtime drift\"}' >/dev/null; osmium-gotify drift --credential alerts:/etc/gotify-user-password --output /tmp/gotify-drift.json; test \"$(sha256sum /var/lib/gotify/.osmium-ledger.json | cut -d' ' -f1)\" = \"$ledger_before\"")
      vm.succeed("jq -e '.complete == false and any(.classifications[]; .kind == \"changed\" and .resource == \"application\")' /tmp/gotify-drift.json")
      vm.succeed("osmium-gotify convert --input /tmp/gotify-drift.json --output /tmp/gotify-candidate.json")
      vm.succeed("jq -e '.complete == false and .declaration.services.osmium.gotify.applications != null and .secrets.redacted == true' /tmp/gotify-candidate.json")
      vm.succeed("! grep -E -i '${adminPassword}|${userPassword}|password_digest|password_salt|gtfya\\.' /tmp/gotify-drift.json /tmp/gotify-candidate.json")
    '' else if mode == "provisioning" then ''
      vm.succeed("cp /var/lib/gotify/credentials/alerts.token /tmp/managed-token; curl --fail --silent -u gotify-admin:${adminPassword} -H 'Content-Type: application/json' -X POST http://127.0.0.1:8080/user -d '{\"name\":\"external\",\"pass\":\"${externalPassword}\",\"admin\":false}' >/dev/null")
      vm.succeed("curl --fail --silent -u external:${externalPassword} -H 'Content-Type: application/json' -X POST http://127.0.0.1:8080/application -d '{\"name\":\"external-client\",\"description\":\"Unrelated runtime app\"}' >/tmp/external-app.json")
      vm.succeed("external_token=$(jq -r .token /tmp/external-app.json); curl --fail --silent -H 'Content-Type: application/json' -X POST \"http://127.0.0.1:8080/message?token=$external_token\" -d '{\"message\":\"before cleanup\"}' >/dev/null")
      vm.succeed("jq '(.applications[] | select(.declaration == \"alerts\")).declaration = \"removed-alerts\"' /var/lib/gotify/.osmium-ledger.json > /tmp/ledger.json && install -o gotify -g gotify -m 0640 /tmp/ledger.json /var/lib/gotify/.osmium-ledger.json")
      vm.succeed("systemctl restart osmium-gotify-reconcile.service")
      vm.succeed("test -s /var/lib/gotify/credentials/alerts.token && ! cmp /tmp/managed-token /var/lib/gotify/credentials/alerts.token")
      vm.fail("managed_token=$(cat /tmp/managed-token); curl --fail --silent -H \"Content-Type: application/json\" -X POST \"http://127.0.0.1:8080/message?token=$managed_token\" -d '{\"message\":\"removed\"}'")
      vm.succeed("external_token=$(jq -r .token /tmp/external-app.json); curl --fail --silent -H 'Content-Type: application/json' -X POST \"http://127.0.0.1:8080/message?token=$external_token\" -d '{\"message\":\"after cleanup\"}' >/dev/null")
      vm.succeed("jq -e '.applications | length == 1 and .[0].declaration == \"alerts\"' /var/lib/gotify/.osmium-ledger.json")
      vm.succeed("curl --fail --silent -u alerts:gotify-user-password http://127.0.0.1:8080/application | jq -e 'length == 1 and .[0].name == \"alerts-client\"'")
      vm.succeed("! grep -E -i '${adminPassword}|${userPassword}|${externalPassword}|gtfya\\.' /var/lib/gotify/.osmium-ledger.json")
      vm.succeed("jq '.users += [{declaration:\"removed-user\",username:\"removed-user\",id:999,admin:false,password_salt:\"redacted\",password_digest:\"redacted\",status:\"success\"}]' /var/lib/gotify/.osmium-ledger.json > /tmp/ledger.json && install -o gotify -g gotify -m 0640 /tmp/ledger.json /var/lib/gotify/.osmium-ledger.json")
      vm.fail("systemctl restart osmium-gotify-reconcile.service")
      vm.succeed("curl --fail --silent -H 'Content-Type: application/json' -X POST \"http://127.0.0.1:8080/message?token=$(cat /var/lib/gotify/credentials/alerts.token)\" -d '{\"message\":\"managed user removal remained non-destructive\"}' >/dev/null")
    '' else ''
      vm.succeed("curl --fail --silent -u gotify-admin:${adminPassword} -H 'Content-Type: application/json' -X POST http://127.0.0.1:8080/user -d '{\"name\":\"external\",\"pass\":\"${externalPassword}\",\"admin\":false}' >/dev/null")
      vm.succeed("curl --fail --silent -u external:${externalPassword} -H 'Content-Type: application/json' -X POST http://127.0.0.1:8080/application -d '{\"name\":\"external-client\",\"description\":\"External runtime app\"}' >/tmp/external-app.json")
      vm.succeed("osmium-gotify capture --credential external:/etc/gotify-external-password --output /tmp/gotify-capture.json")
      vm.succeed("jq -e '.complete == false and (.applications[] | select(.owner == \"external\" and .name == \"external-client\" and .token_output_required == true))' /tmp/gotify-capture.json")
      vm.succeed("osmium-gotify convert --input /tmp/gotify-capture.json --output /tmp/gotify-candidate.json")
      vm.succeed("jq -e '.complete == false and .declaration.services.osmium.gotify.users.external != null' /tmp/gotify-candidate.json")
      vm.succeed("! grep -E -i '${adminPassword}|${userPassword}|${externalPassword}|gtfya\\.' /tmp/gotify-capture.json /tmp/gotify-candidate.json")
    ''}
    vm.shutdown()
  '';
}
