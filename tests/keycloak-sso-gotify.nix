{ pkgs, lib, module, microvm }:

let
  keycloakAdminPassword = "keycloak-admin-password";
  databasePassword = "keycloak-database-password";
  clientSecret = "gotify-keycloak-client-secret";
  cookieSecret = "0123456789abcdef0123456789abcdef";
  gotifyAdminPassword = "gotify-admin-password";
  browserPassword = "gotify-browser-password";
  machinePassword = "gotify-machine-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-keycloak-sso-gotify";

  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    system.stateVersion = "25.05";
    boot.loader.grub.devices = [ "/dev/vda" ];
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 1536;
      interfaces = [{ type = "user"; id = "kcgotify"; mac = "02:00:00:00:00:61"; }];
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
      clients.gotify = {
        realm = "example";
        clientId = "gotify";
        public = false;
        secretFile = "/etc/gotify-keycloak-client-secret";
        flows = [ "authorization-code" "password" ];
        scopes = [ "profile" "email" ];
        redirectUris = [ "http://localhost:8082/oauth2/callback" ];
      };
      users.alice = {
        realm = "example";
        username = "alice";
        email = "alice@example.invalid";
        firstName = "Alice";
        lastName = "Allowed";
        passwordFile = "/etc/gotify-browser-password";
      };
      users.bob = {
        realm = "example";
        username = "bob";
        email = "bob@example.invalid";
        firstName = "Bob";
        lastName = "Denied";
        passwordFile = "/etc/gotify-browser-password";
      };
    };

    services.osmium.gotify = {
      enable = true;
      httpPort = 8081;
      hostHttpPort = 38081;
      admin = { enable = true; username = "gotify-admin"; passwordFile = "/etc/gotify-admin-password"; };
      users.browser = { username = "browser"; passwordFile = "/etc/gotify-browser-password"; };
      users.machine = { username = "machine"; passwordFile = "/etc/gotify-machine-password"; };
      applications.browser = {
        owner = "browser";
        name = "browser-adapter";
        output = { secretPath = "/var/lib/gotify/credentials/browser.token"; owner = "root"; group = "root"; mode = "0400"; };
      };
      applications.machine = {
        owner = "machine";
        name = "machine-client";
        output = { secretPath = "/var/lib/gotify/credentials/machine.token"; owner = "root"; group = "root"; mode = "0400"; };
      };
      sso = {
        enable = true;
        keycloak = { realm = "example"; client = "gotify"; };
        callbackUrl = "http://localhost:8082/oauth2/callback";
        clientSecretFile = "/etc/gotify-keycloak-client-secret";
        cookieSecretFile = "/etc/gotify-cookie-secret";
        browserPort = 8082;
        hostBrowserPort = 38082;
        machinePort = 8083;
        allowedEmails = [ "alice@example.invalid" ];
        browserPrincipal = { user = "browser"; application = "browser"; };
      };
    };

    environment.etc."keycloak-admin-password" = { text = "${keycloakAdminPassword}\n"; mode = "0400"; };
    environment.etc."keycloak-database-password" = { text = "${databasePassword}\n"; mode = "0400"; };
    environment.etc."gotify-keycloak-client-secret" = { text = clientSecret; mode = "0400"; user = "oauth2-proxy"; group = "oauth2-proxy"; };
    environment.etc."gotify-cookie-secret" = { text = cookieSecret; mode = "0400"; user = "oauth2-proxy"; group = "oauth2-proxy"; };
    environment.etc."gotify-admin-password" = { text = "${gotifyAdminPassword}\n"; mode = "0400"; user = "gotify"; group = "gotify"; };
    environment.etc."gotify-browser-password" = { text = "${browserPassword}\n"; mode = "0400"; user = "gotify"; group = "gotify"; };
    environment.etc."gotify-machine-password" = { text = "${machinePassword}\n"; mode = "0400"; user = "gotify"; group = "gotify"; };
    environment.systemPackages = with pkgs; [ curl jq ];
  };

  testScript = ''
    start_all()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("gotify-server.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.wait_for_unit("osmium-gotify-sso-config.service")
    vm.wait_for_unit("oauth2-proxy.service")
    vm.wait_for_open_port(4180)
    vm.wait_for_unit("nginx.service")
    vm.succeed("test -s /var/lib/gotify/credentials/browser.token")

    # This follows the live Keycloak authorization-code form and redirects.
    vm.succeed("rm -f /tmp/gotify.cookies; curl --silent --show-error -L -c /tmp/gotify.cookies -b /tmp/gotify.cookies http://localhost:8082/oauth2/start?rd=/current/user -o /tmp/keycloak-login.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/keycloak-login.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); test -n \"$action\"; curl --silent --show-error -L -c /tmp/gotify.cookies -b /tmp/gotify.cookies --data-urlencode username=alice --data-urlencode password=${browserPassword} \"$action\" -o /tmp/gotify-login-result; curl --fail --silent --show-error -b /tmp/gotify.cookies -H 'Content-Type: application/json' -X POST http://localhost:8082/message -d '{\"message\":\"browser\"}' | jq -e '.message == \"browser\"'")
    vm.succeed("rm -f /tmp/gotify-denied.cookies; curl --fail --silent --show-error -L -c /tmp/gotify-denied.cookies -b /tmp/gotify-denied.cookies http://localhost:8082/oauth2/start?rd=/current/user -o /tmp/keycloak-denied.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/keycloak-denied.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); test -n \"$action\"; curl --silent --show-error -L -c /tmp/gotify-denied.cookies -b /tmp/gotify-denied.cookies --data-urlencode username=bob --data-urlencode password=${browserPassword} \"$action\" -o /tmp/gotify-denied-result.html")
    vm.fail("curl --fail --silent --show-error -b /tmp/gotify-denied.cookies http://localhost:8082/oauth2/auth")

    # The machine route remains token-native and never redirects to Keycloak.
    vm.succeed("curl --fail --silent -H 'Content-Type: application/json' -X POST http://localhost:8083/message?token=$(cat /var/lib/gotify/credentials/machine.token) -d '{\"message\":\"machine\"}'")
    vm.fail("curl --fail --silent -H 'Content-Type: application/json' -X POST http://localhost:8083/message?token=invalid-token -d '{\"message\":\"invalid\"}'")
    vm.fail("curl --fail --silent http://127.0.0.1:8081/current/user")
    vm.succeed("printf 'gotify-keycloak-client-secret-rotated\\n' > /etc/gotify-keycloak-client-secret; systemctl restart osmium-gotify-sso-reload.service")
    vm.fail("curl --fail --silent -b /tmp/gotify.cookies http://localhost:8082/current/user")
    vm.succeed("printf '${clientSecret}\\n' > /etc/gotify-keycloak-client-secret; systemctl restart osmium-gotify-sso-reload.service")
    vm.shutdown()
  '';
}
