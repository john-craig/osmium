{ pkgs, lib, module, microvm }:

let
  base = {
    system.stateVersion = "25.05";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
    services.osmium.keycloak = {
      enable = true;
      allowInsecureHttp = true;
      issuer = "http://127.0.0.1:18080";
      admin.passwordFile = "/run/keycloak-admin-password";
      database.passwordFile = "/run/keycloak-database-password";
      realms.example = { name = "example"; };
      clientScopes.profile = { realm = "example"; name = "profile"; };
      realmRoles.reader = { realm = "example"; name = "reader"; };
      groups.readers = { realm = "example"; name = "readers"; realmRoles = [ "reader" ]; };
      clients.browser = {
        realm = "example";
        clientId = "browser";
        public = true;
        flows = [ "authorization-code" "password" ];
        redirectUris = [ "http://127.0.0.1:18081/callback" ];
      };
      clients.confidential = {
        realm = "example";
        clientId = "confidential";
        public = false;
        secretFile = "/run/confidential-secret";
        flows = [ "password" ];
      };
      reverseConfiguration.enable = true;
      users.alice = {
        realm = "example";
        username = "alice";
        email = "alice@example.invalid";
        firstName = "Alice";
        lastName = "Example";
        passwordFile = "/run/alice-password";
        groups = [ "readers" ];
        realmRoles = [ "reader" ];
      };
    };
  };
  evaluates = extra: (builtins.tryEval (
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ module base extra ];
    }).config.system.build.toplevel
  )).success;
in
assert evaluates { };
assert !evaluates { services.osmium.keycloak.issuer = "not-a-url"; };
assert !evaluates { services.osmium.keycloak.httpPath = "../unsafe"; };
assert !evaluates { services.osmium.keycloak.tls.certificateFile = "/run/keycloak.crt"; };
assert !evaluates { services.osmium.keycloak.clients.browser.redirectUris = [ "http://example.invalid/callback" ]; services.osmium.keycloak.allowInsecureHttp = false; };
assert !evaluates { services.osmium.keycloak.clients.secret = { realm = "example"; clientId = "secret"; public = false; }; };
assert !evaluates { services.osmium.keycloak.hostHttpsPort = 8080; };

pkgs.testers.runNixOSTest {
  name = "osmium-keycloak";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 1024;
      interfaces = [{ type = "user"; id = "keycloak-test"; mac = "02:00:00:00:00:41"; }];
    };
    virtualisation.graphics = false;
    environment.etc."keycloak-admin-password" = { text = "not-used-by-evaluation\n"; mode = "0400"; };
    environment.etc."keycloak-database-password" = { text = "database-password\n"; mode = "0400"; };
    environment.etc."alice-password" = { text = "alice-password\n"; mode = "0400"; };
    environment.etc."confidential-secret" = { text = "confidential-secret\n"; mode = "0400"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
    services.osmium.keycloak = base.services.osmium.keycloak // {
      admin.passwordFile = "/etc/keycloak-admin-password";
      database.passwordFile = "/etc/keycloak-database-password";
      users.alice = base.services.osmium.keycloak.users.alice // { passwordFile = "/etc/alice-password"; };
      clients = base.services.osmium.keycloak.clients // {
        confidential = base.services.osmium.keycloak.clients.confidential // { secretFile = "/etc/confidential-secret"; };
      };
    };
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.succeed("test \"$(systemctl show -p Result --value osmium-keycloak-reconcile.service)\" = success")
    vm.wait_for_open_port(8080)
    vm.succeed("curl --fail http://127.0.0.1:8080/realms/master/.well-known/openid-configuration | jq -e '.issuer | startswith(\"http://127.0.0.1:18080\")'")
    vm.succeed("curl --fail http://127.0.0.1:8080/realms/example/.well-known/openid-configuration | jq -e '.issuer | startswith(\"http://127.0.0.1:18080\")'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=not-used-by-evaluation http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8080/admin/realms/example/clients | jq -e 'any(.[]; .clientId == \"browser\")'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=not-used-by-evaluation http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8080/admin/realms/example/client-scopes | jq -e 'any(.[]; .name == \"profile\")'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=not-used-by-evaluation http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8080/admin/realms/example/roles/reader | jq -e '.name == \"reader\"'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=not-used-by-evaluation http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8080/admin/realms/example/groups | jq -e 'any(.[]; .name == \"readers\")'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=not-used-by-evaluation http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8080/admin/realms/example/users?username=alice | jq -e '.[0].username == \"alice\" and .[0].emailVerified == true and .[0].requiredActions == []'")
    vm.succeed("osmium-keycloak-observe --output /run/keycloak-observation.json")
    vm.succeed("jq -e '.secrets.excluded == true and (.realms | any(.realm == \"example\")) and (.users | any(.username == \"alice\"))' /run/keycloak-observation.json")
    vm.succeed("osmium-keycloak-candidate --input /run/keycloak-observation.json > /run/keycloak-candidate.json")
    vm.succeed("jq -e '.complete == false and .activation_ready == false and (.unresolved | any(. == \"users.*.passwordFile\"))' /run/keycloak-candidate.json")
    vm.succeed("jq -e '.schema_version == 2 and (.credentials.admin.fingerprint | type == \"string\") and (.credentials.users.alice.fingerprint | type == \"string\") and (.credentials.clients.confidential.fingerprint | type == \"string\") and (. | tostring | contains(\"not-used-by-evaluation\") | not)' /var/lib/keycloak/.osmium-ledger.json")
    vm.succeed("curl --fail --silent -u confidential:confidential-secret http://127.0.0.1:8080/realms/example/protocol/openid-connect/token -d grant_type=client_credentials -d scope=openid | jq -e '.access_token != null'")
    vm.succeed("printf 'admin-rotated\\n' > /etc/keycloak-admin-password; printf 'alice-rotated\\n' > /etc/alice-password; printf 'confidential-rotated\\n' > /etc/confidential-secret; systemctl restart osmium-keycloak-reconcile.service")
    vm.fail("curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=not-used-by-evaluation http://127.0.0.1:8080/realms/master/protocol/openid-connect/token")
    vm.succeed("curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=admin-rotated http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -e '.access_token != null'")
    vm.fail("curl --fail --silent -d grant_type=password -d client_id=browser -d username=alice --data-urlencode password=alice-password http://127.0.0.1:8080/realms/example/protocol/openid-connect/token")
    vm.succeed("curl --fail --silent -d grant_type=password -d client_id=browser -d username=alice --data-urlencode password=alice-rotated -d scope=openid http://127.0.0.1:8080/realms/example/protocol/openid-connect/token | jq -e '.access_token != null'")
    vm.succeed("curl --fail --silent -u confidential:confidential-rotated http://127.0.0.1:8080/realms/example/protocol/openid-connect/token -d grant_type=client_credentials | jq -e '.access_token != null'")
    vm.succeed("printf '\\n' > /etc/keycloak-admin-password; systemctl restart osmium-keycloak-reconcile.service || true; curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=admin-rotated http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -e '.access_token != null'; printf 'admin-rotated\\n' > /etc/keycloak-admin-password; systemctl reset-failed osmium-keycloak-reconcile.service || true; systemctl restart osmium-keycloak-reconcile.service")
    vm.succeed("! grep -E -i 'not-used-by-evaluation|alice-password|confidential-secret|admin-rotated|alice-rotated|confidential-rotated' /var/lib/keycloak/.osmium-ledger.json /run/keycloak-observation.json /run/keycloak-candidate.json || true")
  '';
}
