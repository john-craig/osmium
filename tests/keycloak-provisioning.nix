{ pkgs, module, microvm, mode ? "provisioning" }:

let
  adminPassword = "provisioning-admin-password";
  userPassword = "provisioning-user-password";
  clientSecret = "provisioning-client-secret";
in
pkgs.testers.runNixOSTest {
  name = "osmium-keycloak-${mode}";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 1024;
      interfaces = [{ type = "user"; id = "kc-${builtins.substring 0 11 mode}"; mac = "02:00:00:00:00:42"; }];
    };
    services.osmium.keycloak = {
      enable = true;
      allowInsecureHttp = true;
      issuer = "http://127.0.0.1:18082";
      admin.passwordFile = "/etc/keycloak-admin-password";
      database.passwordFile = "/etc/database-password";
      realms.example = { name = "example"; };
      realmRoles.reader = { realm = "example"; name = "reader"; };
      groups.readers = { realm = "example"; name = "readers"; realmRoles = [ "reader" ]; };
      clients.password = {
        realm = "example";
        clientId = "password-client";
        public = true;
        flows = [ "password" ];
      };
      clients.confidential = {
        realm = "example";
        clientId = "confidential-client";
        public = false;
        secretFile = "/etc/client-secret";
        flows = [ "password" ];
      };
      users.alice = {
        realm = "example";
        username = "alice";
        email = "alice@example.invalid";
        firstName = "Alice";
        lastName = "Example";
        passwordFile = "/etc/user-password";
        groups = [ "readers" ];
        realmRoles = [ "reader" ];
      };
      reverseConfiguration.enable = true;
    };
    environment.etc."keycloak-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; };
    environment.etc."user-password" = { text = "${userPassword}\n"; mode = "0400"; };
    environment.etc."client-secret" = { text = "${clientSecret}\n"; mode = "0400"; };
    environment.etc."database-password" = { text = "provisioning-database-password\n"; mode = "0400"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.wait_for_open_port(8080)
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${adminPassword} http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail --silent -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8080/admin/realms/example/users?username=alice | jq -e '.[0].username == \"alice\" and .[0].emailVerified == true and .[0].requiredActions == []'")
    ${if mode == "provisioning" then ''
      vm.succeed("curl --fail --silent -d grant_type=password -d client_id=password-client -d username=alice --data-urlencode password=${userPassword} -d scope=openid http://127.0.0.1:8080/realms/example/protocol/openid-connect/token | jq -e '.access_token != null'")
      vm.succeed("curl --fail --silent -u confidential-client:${clientSecret} http://127.0.0.1:8080/realms/example/protocol/openid-connect/token -d grant_type=client_credentials -d scope=openid | jq -e '.access_token != null'")
      vm.succeed("before=$(sha256sum /var/lib/keycloak/.osmium-ledger.json | cut -d' ' -f1); systemctl restart osmium-keycloak-reconcile.service; test \"$(sha256sum /var/lib/keycloak/.osmium-ledger.json | cut -d' ' -f1)\" = \"$before\"")
      vm.succeed("jq -e '.schema_version == 2 and .resources.secret_values == \"excluded\" and (.credentials | tostring | contains(\"${adminPassword}\") | not)' /var/lib/keycloak/.osmium-ledger.json")
    '' else if mode == "drift-reverse-configuration" then ''
      vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${adminPassword} http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail --silent -X PUT -H \"Authorization: Bearer $admin_token\" -H 'Content-Type: application/json' http://127.0.0.1:8080/admin/realms/example -d '{\"realm\":\"example\",\"displayName\":\"Runtime drift\",\"enabled\":true}' >/dev/null; cp /var/lib/keycloak/.osmium-ledger.json /tmp/ledger-before; osmium-keycloak-observe --output /tmp/observation.json; osmium-keycloak-candidate --input /tmp/observation.json > /tmp/candidate.json; cmp /tmp/ledger-before /var/lib/keycloak/.osmium-ledger.json; jq -e '.source.review_only == true and (.realms | any(.displayName == \"Runtime drift\")) and .secrets.excluded == true' /tmp/observation.json; jq -e '.complete == false and .activation_ready == false and (.unresolved | any(. == \"clients.*.secretFile\"))' /tmp/candidate.json; ! grep -E -i '${adminPassword}|${userPassword}|${clientSecret}' /tmp/observation.json /tmp/candidate.json")
    '' else ''
      vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${adminPassword} http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail --silent -X POST -H \"Authorization: Bearer $admin_token\" -H 'Content-Type: application/json' http://127.0.0.1:8080/admin/realms -d '{\"realm\":\"captured\",\"enabled\":true,\"displayName\":\"Captured externally\"}' >/dev/null; curl --fail --silent -X POST -H \"Authorization: Bearer $admin_token\" -H 'Content-Type: application/json' http://127.0.0.1:8080/admin/realms/captured/clients -d '{\"clientId\":\"external-client\",\"publicClient\":true,\"enabled\":true,\"redirectUris\":[\"http://127.0.0.1/callback\"]}' >/dev/null; cp /var/lib/keycloak/.osmium-ledger.json /tmp/ledger-before; osmium-keycloak-observe --output /tmp/capture.json; osmium-keycloak-candidate --input /tmp/capture.json > /tmp/candidate.json; cmp /tmp/ledger-before /var/lib/keycloak/.osmium-ledger.json; jq -e '.source.origin == \"runtime-observation\" and (.realms | any(.realm == \"captured\")) and (.clients | any(.clientId == \"external-client\"))' /tmp/capture.json; jq -e '.complete == false and .activation_ready == false and (.findings | any(. == \"operator_review_required\"))' /tmp/candidate.json; ! grep -E -i '${adminPassword}|${userPassword}|${clientSecret}' /tmp/capture.json /tmp/candidate.json")
    ''}
    vm.shutdown()
  '';
}
