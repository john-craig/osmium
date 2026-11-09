{ pkgs, lib, module, microvm }:

let
  adminPassword = "gitea-local-admin-password";
  keycloakAdminPassword = "keycloak-admin-password";
  databasePassword = "keycloak-database-password";
  userPassword = "gitea-sso-user-password";
  clientSecret = "gitea-keycloak-client-secret";
in
pkgs.testers.runNixOSTest {
  name = "osmium-keycloak-sso-gitea";

  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    system.stateVersion = "25.05";
    boot.loader.grub.devices = [ "/dev/vda" ];

    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 1536;
      interfaces = [{ type = "user"; id = "kcgitea"; mac = "02:00:00:00:00:51"; }];
    };

    virtualisation.graphics = false;
    virtualisation.diskSize = 8192;
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; options = [ "mode=755" ]; neededForBoot = true; };
    fileSystems."/persistent" = { device = "/dev/vda"; fsType = "ext4"; neededForBoot = true; };

    services.osmium.keycloak = {
      enable = true;
      allowInsecureHttp = true;
      issuer = "http://127.0.0.1:8080";
      admin.passwordFile = "/etc/keycloak-admin-password";
      database.passwordFile = "/etc/keycloak-database-password";
      realms.example = { name = "example"; };
      clients.gitea = {
        realm = "example";
        clientId = "gitea";
        public = false;
        secretFile = "/etc/gitea-keycloak-client-secret";
        flows = [ "authorization-code" "password" ];
        scopes = [ "profile" "email" ];
        redirectUris = [ "http://localhost:3000/user/oauth2/Keycloak/callback" ];
      };
      users.alice = {
        realm = "example";
        username = "alice";
        email = "alice@example.invalid";
        firstName = "Alice";
        lastName = "Example";
        emailVerified = true;
        passwordFile = "/etc/gitea-sso-user-password";
      };
      users.bob = {
        realm = "example";
        username = "bob";
        email = "bob@example.invalid";
        passwordFile = "/etc/gitea-sso-user-password";
      };
    };

    services.osmium.gitea = {
      enable = true;
      hostHttpPort = 3000;
      hostSshPort = 2222;
      settings.service.DISABLE_REGISTRATION = true;
      settings.oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        USERNAME = "preferred_username";
      };
      admin = {
        enable = true;
        username = "local-admin";
        email = "local-admin@example.invalid";
        passwordFile = "/etc/gitea-admin-password";
      };
      sso = {
        enable = true;
        keycloak = { realm = "example"; client = "gitea"; };
        callbackUrl = "http://localhost:3000/user/oauth2/Keycloak/callback";
        clientSecretFile = "/etc/gitea-keycloak-client-secret";
        requiredClaim = { name = "email"; value = "alice@example.invalid"; };
        groupClaimName = "groups";
      };
    };

    # Keycloak's first PostgreSQL/Liquibase startup is slow in this combined
    # fixture; avoid racing Gitea's bounded start-pre migration against it.
    systemd.services.gitea.after = [ "keycloak.service" ];
    systemd.services.gitea.serviceConfig.TimeoutStartSec = lib.mkForce "10min";

    environment.etc."keycloak-admin-password" = { text = "${keycloakAdminPassword}\n"; mode = "0400"; };
    environment.etc."keycloak-database-password" = { text = "${databasePassword}\n"; mode = "0400"; };
    environment.etc."gitea-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
    environment.etc."gitea-sso-user-password" = { text = "${userPassword}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
    environment.etc."gitea-keycloak-client-secret" = { text = "${clientSecret}\n"; mode = "0400"; user = "gitea"; group = "gitea"; };
    environment.systemPackages = with pkgs; [ curl gitea jq python3 ];
  };

  testScript = ''
    start_all()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("gitea.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.succeed("systemctl show -p Result --value osmium-gitea-admin-bootstrap.service | grep -qx success")
    vm.wait_for_unit("osmium-gitea-keycloak-sso.service")
    vm.succeed("runuser -u gitea -- gitea --config /var/lib/gitea/custom/conf/app.ini admin auth list | grep -F Keycloak")
    vm.succeed("jq -e '.provider == \"openidConnect\" and .source_name == \"Keycloak\" and (.fingerprint | length) == 64 and (. | tostring | contains(\"${clientSecret}\") | not)' /var/lib/gitea/.osmium-keycloak-sso.json")
    vm.succeed("curl --fail --silent -u local-admin:${adminPassword} http://127.0.0.1:3000/api/v1/user | jq -e '.login == \"local-admin\" and .is_admin == true'")

    # Follow the live Gitea redirect and Keycloak login form; no fixture token is minted.
    vm.succeed("rm -f /tmp/gitea.cookies; curl --fail --silent --show-error -L -c /tmp/gitea.cookies -b /tmp/gitea.cookies http://localhost:3000/user/oauth2/Keycloak -o /tmp/keycloak-login.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/keycloak-login.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); test -n \"$action\"; curl --fail --silent --show-error -L -c /tmp/gitea.cookies -b /tmp/gitea.cookies --data-urlencode username=alice --data-urlencode password=${userPassword} \"$action\" -o /tmp/gitea-after-login.html; curl --fail --silent --show-error -b /tmp/gitea.cookies http://localhost:3000/ -o /tmp/gitea-home.html; grep -F 'alice' /tmp/gitea-home.html; curl --fail --silent --show-error -u local-admin:${adminPassword} http://localhost:3000/api/v1/users/alice | jq -e '.login == \"alice\" and .is_admin == false'")
    vm.succeed("curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${keycloakAdminPassword} http://127.0.0.1:8080/realms/master/protocol/openid-connect/token | jq -r .access_token > /tmp/admin-token; token=$(cat /tmp/admin-token); curl --fail --silent -X PUT -H \"Authorization: Bearer $token\" -H 'Content-Type: application/json' http://127.0.0.1:8080/admin/realms/example/users/$(curl --fail --silent -H \"Authorization: Bearer $token\" 'http://127.0.0.1:8080/admin/realms/example/users?username=bob' | jq -r '.[0].id') -d '{\"enabled\":false}'")
    vm.succeed("rm -f /tmp/gitea-denied.cookies; curl --fail --silent --show-error -L -c /tmp/gitea-denied.cookies -b /tmp/gitea-denied.cookies http://localhost:3000/user/oauth2/Keycloak -o /tmp/keycloak-denied.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/keycloak-denied.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); curl --silent --show-error -L -c /tmp/gitea-denied.cookies -b /tmp/gitea-denied.cookies --data-urlencode username=bob --data-urlencode password=${userPassword} \"$action\" -o /tmp/gitea-denied-result.html; ! curl --silent --fail -b /tmp/gitea-denied.cookies http://localhost:3000/api/v1/user; ! curl --silent --fail -u local-admin:${adminPassword} http://localhost:3000/api/v1/users/bob")

    vm.succeed("printf 'gitea-keycloak-client-secret-rotated\\n' > /etc/gitea-keycloak-client-secret; systemctl restart osmium-keycloak-reconcile.service; systemctl restart osmium-gitea-keycloak-sso.service; curl --fail --silent -u gitea:gitea-keycloak-client-secret-rotated http://127.0.0.1:8080/realms/example/protocol/openid-connect/token -d grant_type=client_credentials | jq -e '.access_token != null'; curl --fail --silent -u local-admin:${adminPassword} http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("test \"$(cat /run/osmium-keycloak/client-gitea)\" = gitea-keycloak-client-secret-rotated")
    vm.succeed("printf 'invalid-client-secret\\n' > /etc/gitea-keycloak-client-secret; systemctl restart osmium-keycloak-reconcile.service || true; systemctl restart osmium-gitea-keycloak-sso.service || true; printf 'gitea-keycloak-client-secret-rotated\\n' > /etc/gitea-keycloak-client-secret; systemctl reset-failed osmium-keycloak-reconcile.service osmium-gitea-keycloak-sso.service; systemctl restart osmium-keycloak-reconcile.service; systemctl restart osmium-gitea-keycloak-sso.service")

    vm.shutdown()
    vm.start()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("gitea.service")
    vm.wait_for_unit("osmium-gitea-keycloak-sso.service")
    vm.succeed("curl --fail --silent -u local-admin:${adminPassword} http://127.0.0.1:3000/api/v1/user | jq -e '.login == \"local-admin\" and .is_admin == true'")
    vm.succeed("test -s /var/lib/gitea/.osmium-keycloak-sso.json")
  '';
}
