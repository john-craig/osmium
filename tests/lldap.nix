{ pkgs, lib, module, microvm, mode ? "service" }:

let
  keycloakAdminPassword = "keycloak-admin-password";
  keycloakDatabasePassword = "keycloak-database-password";
  gatewayClientSecret = "lldap-gateway-client-secret";
  gatewayCookieSecret = "0123456789abcdef0123456789abcdef";
  operatorPassword = "lldap-operator-password";
in

pkgs.testers.runNixOSTest {
  name = "osmium-lldap-${mode}";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "lldapvm"; mac = "02:00:00:00:00:61"; } ];
    };
    services.osmium.keycloak = {
      enable = true;
      allowInsecureHttp = true;
      issuer = "http://127.0.0.1:8080";
      admin.passwordFile = "/etc/keycloak-admin-password";
      database.passwordFile = "/etc/keycloak-database-password";
      realms.example = { name = "example"; };
      clients.lldapGateway = {
        realm = "example";
        clientId = "lldap-gateway";
        public = false;
        secretFile = "/etc/lldap-gateway-client-secret";
        flows = [ "authorization-code" "password" ];
        scopes = [ "profile" "email" ];
        redirectUris = [ "https://localhost:17172/oauth2/callback" ];
      };
      users.operator = { realm = "example"; username = "operator"; email = "operator@example.invalid"; firstName = "Allowed"; lastName = "Operator"; passwordFile = "/etc/lldap-operator-password"; };
      users.denied = { realm = "example"; username = "denied"; email = "denied@example.invalid"; firstName = "Denied"; lastName = "Operator"; passwordFile = "/etc/lldap-operator-password"; };
    };
    services.osmium.lldap = {
      enable = true;
      baseDn = "dc=example,dc=com";
      httpUrl = "https://lldap.example.invalid";
      hostLdapPort = 3891;
      hostHttpPort = null;
      admin = { username = "admin"; email = "admin@example.com"; passwordFile = "/etc/lldap-admin-password"; };
      jwtSecretFile = "/etc/lldap-jwt-secret";
      keySeedFile = "/etc/lldap-key-seed";
      ldaps = {
        enable = true;
        hostPort = 6361;
        certificateFile = "/var/lib/lldap/test-certificate.pem";
        keyFile = "/var/lib/lldap/test-key.pem";
      };
      gateway = {
        enable = true;
        keycloak = { realm = "example"; client = "lldapGateway"; };
        callbackUrl = "https://localhost:17172/oauth2/callback";
        clientSecretFile = "/etc/lldap-gateway-client-secret";
        cookieSecretFile = "/etc/lldap-gateway-cookie-secret";
        tls = { certificateFile = "/etc/lldap-gateway-certificate.pem"; keyFile = "/etc/lldap-gateway-key.pem"; };
        browserPort = 17172;
        hostBrowserPort = 17172;
        machinePort = 17173;
        operator.allowedEmails = [ "operator@example.invalid" ];
      };
    };
    environment.etc."keycloak-admin-password" = { text = "${keycloakAdminPassword}\n"; mode = "0400"; };
    environment.etc."keycloak-database-password" = { text = "${keycloakDatabasePassword}\n"; mode = "0400"; };
    environment.etc."lldap-gateway-client-secret" = { text = gatewayClientSecret; mode = "0400"; user = "oauth2-proxy"; group = "oauth2-proxy"; };
    environment.etc."lldap-gateway-cookie-secret" = { text = "${gatewayCookieSecret}\n"; mode = "0400"; user = "oauth2-proxy"; group = "oauth2-proxy"; };
    environment.etc."lldap-operator-password" = { text = "${operatorPassword}\n"; mode = "0400"; };
    environment.etc."lldap-admin-password" = { text = "test-admin-password-value\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-jwt-secret" = { text = "lldap-jwt-secret-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-key-seed" = { text = "lldap-key-seed-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    systemd.services.osmium-lldap-test-tls = {
      wantedBy = [ "lldap.service" ];
      before = [ "lldap.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        install -d -o lldap -g lldap -m 0750 /var/lib/lldap
        install -d -o root -g nginx -m 0755 /run/osmium-lldap
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
          -subj /CN=lldap.example.invalid \
          -keyout /var/lib/lldap/test-key.pem -out /var/lib/lldap/test-certificate.pem
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
          -subj /CN=localhost \
          -keyout /etc/lldap-gateway-key.pem -out /etc/lldap-gateway-certificate.pem
        chown lldap:lldap /var/lib/lldap/test-key.pem /var/lib/lldap/test-certificate.pem
        chown nginx:nginx /etc/lldap-gateway-key.pem /etc/lldap-gateway-certificate.pem
        chmod 0400 /var/lib/lldap/test-key.pem
        chmod 0400 /etc/lldap-gateway-key.pem
        chmod 0444 /var/lib/lldap/test-certificate.pem /etc/lldap-gateway-certificate.pem
      '';
    };
    systemd.services.lldap.after = [ "osmium-lldap-test-tls.service" ];
    systemd.services.lldap.requires = [ "osmium-lldap-test-tls.service" ];
    systemd.services.nginx.after = [ "osmium-lldap-test-tls.service" ];
    systemd.services.nginx.requires = [ "osmium-lldap-test-tls.service" ];
    systemd.services.osmium-lldap-gateway-reload.after = [ "osmium-lldap-test-tls.service" ];
    systemd.services.osmium-lldap-gateway-reload.requires = [ "osmium-lldap-test-tls.service" ];
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openldap ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.wait_for_unit("lldap.service")
    vm.wait_for_unit("osmium-lldap-runtime-environment.service")
    vm.wait_for_open_port(3890)
    vm.wait_for_open_port(6360)
    vm.wait_for_unit("oauth2-proxy.service")
    vm.wait_for_unit("nginx.service")
    vm.wait_for_open_port(17172)
    vm.succeed("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=admin,ou=people,dc=example,dc=com' -w test-admin-password-value -b 'dc=example,dc=com' '(uid=admin)' | grep -F 'uid: admin'")
    vm.succeed("LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://127.0.0.1:6360 -D 'uid=admin,ou=people,dc=example,dc=com' -w test-admin-password-value -b 'dc=example,dc=com' '(uid=admin)' | grep -F 'uid: admin'")
    vm.succeed("curl --fail --silent http://127.0.0.1:17170/ | grep -E -i 'LLDAP|login'")
    vm.succeed("test \"$(curl --silent --insecure --max-time 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:17172/)\" = 302")
    vm.succeed("test \"$(curl --silent --insecure -H 'X-Forwarded-User: operator' -o /dev/null -w '%{http_code}' https://127.0.0.1:17172/)\" = 302")
    vm.succeed("rm -f /tmp/lldap.cookies; curl --fail --silent --show-error --insecure -L -c /tmp/lldap.cookies -b /tmp/lldap.cookies https://localhost:17172/oauth2/start?rd=/ -o /tmp/lldap-login.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/lldap-login.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); test -n \"$action\"; curl --fail --silent --show-error --insecure -L -c /tmp/lldap.cookies -b /tmp/lldap.cookies --data-urlencode username=operator --data-urlencode password=${operatorPassword} \"$action\" -o /tmp/lldap-after-login.html")
    vm.succeed("test \"$(curl --silent --insecure -b /tmp/lldap.cookies -o /dev/null -w '%{http_code}' https://localhost:17172/oauth2/auth)\" = 202; curl --fail --silent --show-error --insecure -b /tmp/lldap.cookies https://localhost:17172/ -o /tmp/lldap-home.html")
    vm.fail("curl --fail --silent --max-time 1 http://127.0.0.1:17173/api/graphql")
    vm.fail("curl --fail --silent --max-time 1 -H 'X-Forwarded-User: operator' http://127.0.0.1:17173/api/graphql")
    vm.succeed("test \"$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 1 -H 'Authorization: Bearer invalid' http://127.0.0.1:17173/api/graphql)\" = 401")
    vm.fail("curl --fail --silent --max-time 1 http://127.0.0.1:3890/")
    vm.succeed("test -s /var/lib/lldap/users.db")
    vm.succeed("! grep -aF test-admin-password-value /proc/$(systemctl show -p MainPID --value lldap.service)/cmdline")
    vm.succeed("vm_state=$(sha256sum /var/lib/lldap/users.db | cut -d' ' -f1); systemctl restart lldap.service; test \"$(sha256sum /var/lib/lldap/users.db | cut -d' ' -f1)\" = \"$vm_state\"")
    vm.shutdown()
  '';
}
