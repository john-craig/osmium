{ pkgs, lib, module, microvm }:

let
  adminPassword = "federation-admin-password";
  bindPassword = "federation-bind-password";
  bindPasswordRotated = "federation-bind-password-rotated";
  userPassword = "federation-user-password";
  keycloakPassword = "federation-keycloak-password";
  databasePassword = "federation-database-password";
  base = {
    system.stateVersion = "25.05";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
    services.osmium.lldap = {
      enable = true;
      baseDn = "dc=example,dc=com";
      httpUrl = "https://lldap.example.invalid";
      ldapPort = 3890;
      hostLdapPort = 3892;
      ldaps = {
        enable = true;
        port = 6360;
        hostPort = 6362;
        certificateFile = "/run/lldap-cert.pem";
        keyFile = "/run/lldap-key.pem";
      };
      admin = { username = "admin"; email = "admin@example.com"; passwordFile = "/etc/lldap-admin-password"; };
      jwtSecretFile = "/etc/lldap-jwt-secret";
      keySeedFile = "/etc/lldap-key-seed";
      users.keycloakBind = {
        username = "keycloak-bind";
        email = "keycloak-bind@example.com";
        passwordFile = "/etc/lldap-keycloak-bind-password";
        consumer = "keycloak";
      };
      users.bob = {
        username = "bob";
        email = "bob@example.com";
        passwordFile = "/etc/lldap-bob-password";
        groups = [ "readers" ];
      };
      groups.readers = { displayName = "readers"; users = [ "bob" ]; };
    };
    services.osmium.keycloak = {
      enable = true;
      allowInsecureHttp = true;
      issuer = "http://127.0.0.1:18083";
      httpPort = 8083;
      hostHttpPort = 18083;
      admin.passwordFile = "/etc/keycloak-admin-password";
      database.passwordFile = "/etc/keycloak-database-password";
      realms.example = { name = "example"; };
      clients.password = {
        realm = "example";
        clientId = "password-client";
         public = true;
         flows = [ "password" ];
         includeGroupClaims = true;
      };
      users.local = {
        realm = "example";
        username = "local-user";
        email = "local@example.com";
        firstName = "Local";
        lastName = "User";
        passwordFile = "/etc/keycloak-local-password";
      };
      ldapFederations.directory = {
        realm = "example";
         connectionUrl = "ldaps://127.0.0.1:6360";
         usersDn = "ou=people,dc=example,dc=com";
         groupsDn = "ou=groups,dc=example,dc=com";
        bindDn = "uid=keycloak-bind,ou=people,dc=example,dc=com";
        bindUser = "keycloakBind";
        bindPasswordFile = "/etc/lldap-keycloak-bind-password";
        trustCertificateFile = "/run/lldap-cert.pem";
      };
    };
  };
  evaluates = extra: (builtins.tryEval (
    (lib.nixosSystem { system = "x86_64-linux"; modules = [ module base extra ]; }).config.system.build.toplevel
  )).success;
in
assert evaluates { };
assert !evaluates { services.osmium.keycloak.ldapFederations.directory.connectionUrl = "ldap://127.0.0.1:3890"; };
assert !evaluates { services.osmium.keycloak.ldapFederations.directory.bindPasswordFile = "/nix/store/bind-password"; };
assert !evaluates { services.osmium.keycloak.ldapFederations.directory.bindUser = "missing"; };
assert !evaluates { services.osmium.keycloak.ldapFederations.directory.bindDn = "uid=admin,ou=people,dc=example,dc=com"; };
assert !evaluates { services.osmium.lldap.users.autheliaBind = {
  username = "authelia-bind";
  email = "authelia-bind@example.com";
  passwordFile = "/etc/authelia-bind-password";
  consumer = "keycloak";
}; };

pkgs.testers.runNixOSTest {
  name = "osmium-lldap-keycloak-federation";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    microvm = {
      hypervisor = "qemu";
      vcpu = 4;
      mem = 2048;
      interfaces = [ { type = "user"; id = "lldap-keycloak"; mac = "02:00:00:00:00:64"; } ];
    };
    inherit (base) services;
    environment.etc."lldap-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-jwt-secret" = { text = "federation-jwt-secret-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-key-seed" = { text = "federation-key-seed-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-keycloak-bind-password" = { text = "${bindPassword}\n"; mode = "0400"; };
    environment.etc."lldap-bob-password" = { text = "${userPassword}\n"; mode = "0400"; };
    environment.etc."keycloak-admin-password" = { text = "${keycloakPassword}\n"; mode = "0400"; };
    environment.etc."keycloak-database-password" = { text = "${databasePassword}\n"; mode = "0400"; };
    environment.etc."keycloak-local-password" = { text = "local-password\n"; mode = "0400"; };
    systemd.services.lldap-cert = {
      before = [ "lldap.service" ];
      wantedBy = [ "lldap.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        install -d -m 0755 /run
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
          -keyout /run/lldap-key.pem -out /run/lldap-cert.pem \
          -subj /CN=127.0.0.1 -addext "subjectAltName=IP:127.0.0.1" >/dev/null 2>&1
        chown lldap:lldap /run/lldap-key.pem /run/lldap-cert.pem
        chmod 0400 /run/lldap-key.pem
        chmod 0444 /run/lldap-cert.pem
      '';
    };
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openldap ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("lldap.service")
    vm.wait_for_unit("osmium-lldap-reconcile.service")
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.succeed("systemctl is-active --quiet osmium-keycloak-reconcile.service")
    vm.succeed("LDAPTLS_CACERT=/run/lldap-cert.pem ldapsearch -x -H ldaps://127.0.0.1:6360 -D 'uid=keycloak-bind,ou=people,dc=example,dc=com' -w ${bindPassword} -b 'ou=people,dc=example,dc=com' '(uid=bob)' | grep -F 'uid: bob'")
    vm.fail("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=keycloak-bind,ou=people,dc=example,dc=com' -w ${adminPassword} -b 'dc=example,dc=com' '(uid=bob)'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${keycloakPassword} http://127.0.0.1:8083/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail --silent -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8083/admin/realms/example/components | jq -e 'any(.[]; .providerId == \"ldap\" and .config.connectionUrl[0] == \"ldaps://127.0.0.1:6360\")'")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${keycloakPassword} http://127.0.0.1:8083/realms/master/protocol/openid-connect/token | jq -r .access_token); client_id=$(curl --fail --silent -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8083/admin/realms/example/clients | jq -r '.[] | select(.clientId == \"password-client\") | .id'); curl --fail --silent -H \"Authorization: Bearer $admin_token\" http://127.0.0.1:8083/admin/realms/example/clients/$client_id/protocol-mappers/models | jq -e 'any(.[]; .protocolMapper == \"oidc-group-membership-mapper\" and .config[\"claim.name\"] == \"groups\")'")
    vm.succeed("token=$(curl --fail --silent -d grant_type=password -d client_id=password-client -d username=bob --data-urlencode password=${userPassword} -d scope=openid http://127.0.0.1:8083/realms/example/protocol/openid-connect/token | jq -r .access_token); test -n \"$token\"; payload=$(printf '%s' \"$token\" | cut -d. -f2 | tr '_-' '/+' | awk '{l=length($0)%4; if(l==2) printf \"%s==\",$0; else if(l==3) printf \"%s=\",$0; else printf \"%s\",$0}' | base64 -d); jq -e '.groups | index(\"/readers\") != null' <<<\"$payload\"")
    vm.succeed("admin_token=$(curl --fail --silent -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode password=${keycloakPassword} http://127.0.0.1:8083/realms/master/protocol/openid-connect/token | jq -r .access_token); curl --fail --silent -H \"Authorization: Bearer $admin_token\" 'http://127.0.0.1:8083/admin/realms/example/users?username=local-user' | jq -e '.[0].requiredActions == [] and .[0].enabled == true and .[0].emailVerified == true'")
    vm.succeed("curl --fail --silent -d grant_type=password -d client_id=password-client -d username=local-user --data-urlencode password=local-password -d scope=openid http://127.0.0.1:8083/realms/example/protocol/openid-connect/token | jq -e '.access_token != null'")
    vm.succeed("systemctl mask --runtime osmium-keycloak-reconcile.path osmium-keycloak-reconcile.service; systemctl stop osmium-keycloak-reconcile.path osmium-keycloak-reconcile.service; printf '${bindPasswordRotated}\\n' > /etc/lldap-keycloak-bind-password; systemctl restart osmium-lldap-reconcile.service; systemctl unmask osmium-keycloak-reconcile.service; systemctl start osmium-keycloak-reconcile.service; systemctl unmask osmium-keycloak-reconcile.path; systemctl start osmium-keycloak-reconcile.path")
    vm.fail("LDAPTLS_CACERT=/run/lldap-cert.pem ldapsearch -x -H ldaps://127.0.0.1:6360 -D 'uid=keycloak-bind,ou=people,dc=example,dc=com' -w ${bindPassword} -b 'ou=people,dc=example,dc=com' '(uid=bob)'")
    vm.succeed("LDAPTLS_CACERT=/run/lldap-cert.pem ldapsearch -x -H ldaps://127.0.0.1:6360 -D 'uid=keycloak-bind,ou=people,dc=example,dc=com' -w ${bindPasswordRotated} -b 'ou=people,dc=example,dc=com' '(uid=bob)' | grep -F 'uid: bob'")
    vm.succeed("! grep -E -i '${adminPassword}|${bindPassword}|${bindPasswordRotated}' /var/lib/lldap/.osmium-identities.json /var/lib/keycloak/.osmium-ledger.json")
    vm.shutdown()
  '';
}
