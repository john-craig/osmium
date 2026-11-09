{ pkgs, lib, module, microvm }:

let
  adminPassword = "test-admin-password-value";
  alicePassword = "alice-password-value";
in
pkgs.testers.runNixOSTest {
  name = "osmium-lldap-identities";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "lldap-id"; mac = "02:00:00:00:00:62"; } ];
    };
    services.osmium.lldap = {
      enable = true;
      baseDn = "dc=example,dc=com";
      httpUrl = "https://lldap.example.invalid";
      hostLdapPort = 3892;
      hostHttpPort = null;
      admin = { username = "admin"; email = "admin@example.com"; passwordFile = "/etc/lldap-admin-password"; };
      jwtSecretFile = "/etc/lldap-jwt-secret";
      keySeedFile = "/etc/lldap-key-seed";
      ldaps.enable = false;
      users.alice = {
        username = "alice";
        email = "alice@example.com";
        displayName = "Alice Example";
        firstName = "Alice";
        lastName = "Example";
        passwordFile = "/etc/alice-password";
        groups = [ "readers" ];
        removalPolicy = "delete";
      };
      groups.readers = {
        displayName = "readers";
        users = [ "alice" ];
        removalPolicy = "delete";
      };
    };
    environment.etc."lldap-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-jwt-secret" = { text = "lldap-jwt-secret-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-key-seed" = { text = "lldap-key-seed-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."alice-password" = { text = "${alicePassword}\n"; mode = "0400"; user = "root"; group = "root"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openldap ];
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("lldap.service")
    vm.wait_for_unit("osmium-lldap-reconcile.service")
    vm.succeed("systemctl is-active --quiet osmium-lldap-reconcile.service")
    vm.succeed("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=alice,ou=people,dc=example,dc=com' -w ${alicePassword} -b 'dc=example,dc=com' '(uid=alice)' | grep -F 'uid: alice'")
    vm.succeed("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=alice,ou=people,dc=example,dc=com' -w ${alicePassword} -b 'cn=readers,ou=groups,dc=example,dc=com' -s base '(objectClass=*)' | grep -F 'member: uid=alice,ou=people,dc=example,dc=com'")
    vm.succeed("jq -e '.schema_version == 1 and (.users | any(.declaration == \"alice\" and .fingerprint != null)) and (.groups | any(.declaration == \"readers\" and .id != null))' /var/lib/lldap/.osmium-identities.json")
    vm.succeed("! grep -E -i '${adminPassword}|${alicePassword}|lldap-jwt-secret|lldap-key-seed' /var/lib/lldap/.osmium-identities.json")
    vm.succeed("before=$(sha256sum /var/lib/lldap/.osmium-identities.json | cut -d' ' -f1); systemctl restart osmium-lldap-reconcile.service; test \"$(sha256sum /var/lib/lldap/.osmium-identities.json | cut -d' ' -f1)\" = \"$before\"")
    vm.succeed("printf 'alice-password-rotated\n' > /etc/alice-password; systemctl restart osmium-lldap-reconcile.service")
    vm.fail("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=alice,ou=people,dc=example,dc=com' -w ${alicePassword} -b 'dc=example,dc=com' '(uid=alice)'")
    vm.succeed("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=alice,ou=people,dc=example,dc=com' -w alice-password-rotated -b 'dc=example,dc=com' '(uid=alice)' | grep -F 'uid: alice'")
    vm.succeed("printf '\n' > /etc/alice-password; systemctl restart osmium-lldap-reconcile.service || true; ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=alice,ou=people,dc=example,dc=com' -w alice-password-rotated -b 'dc=example,dc=com' '(uid=alice)' | grep -F 'uid: alice'; printf 'alice-password-rotated\n' > /etc/alice-password; systemctl reset-failed osmium-lldap-reconcile.service || true; systemctl restart osmium-lldap-reconcile.service")
    vm.succeed("test -s /var/lib/lldap/users.db; state=$(sha256sum /var/lib/lldap/users.db | cut -d' ' -f1); systemctl restart lldap.service; test \"$(sha256sum /var/lib/lldap/users.db | cut -d' ' -f1)\" = \"$state\"")
    vm.shutdown()
  '';
}
