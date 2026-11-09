{ pkgs, lib, module, microvm }:

let
  adminPassword = "test-admin-password-value";
  currentPassword = "current-password-value";
in
pkgs.testers.runNixOSTest {
  name = "osmium-lldap-identity-removal";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 768;
      interfaces = [ { type = "user"; id = "lldap-removal"; mac = "02:00:00:00:00:63"; } ];
    };
    services.osmium.lldap = {
      enable = true;
      baseDn = "dc=example,dc=com";
      httpUrl = "https://lldap.example.invalid";
      hostLdapPort = 3893;
      hostHttpPort = null;
      admin = { username = "admin"; email = "admin@example.com"; passwordFile = "/etc/lldap-admin-password"; };
      jwtSecretFile = "/etc/lldap-jwt-secret";
      keySeedFile = "/etc/lldap-key-seed";
      ldaps.enable = false;
      users.current = {
        username = "current";
        email = "current@example.com";
        displayName = "Current User";
        passwordFile = "/etc/current-password";
      };
    };
    environment.etc."lldap-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-jwt-secret" = { text = "lldap-jwt-secret-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."lldap-key-seed" = { text = "lldap-key-seed-012345678901234567890123\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
    environment.etc."current-password" = { text = "${currentPassword}\n"; mode = "0400"; user = "root"; group = "root"; };
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openldap pkgs.lldap ];

    systemd.services.osmium-lldap-seed-removal = {
      description = "Seed LLDAP removal-policy integration state";
      wantedBy = [ "osmium-lldap-reconcile.service" ];
      before = [ "osmium-lldap-reconcile.service" ];
      after = [ "lldap.service" ];
      requires = [ "lldap.service" ];
      path = [ pkgs.curl pkgs.jq ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -eu
        api=http://127.0.0.1:17170
        install -d -m 0700 /var/lib/lldap
        sleep 60
        login_payload=$(jq -cn --arg username admin --arg password ${lib.escapeShellArg adminPassword} '{username:$username,password:$password}')
        token=""
        for attempt in $(seq 1 30); do
          printf '%s' "$login_payload" \
            | curl --silent --max-time 2 -o /run/lldap-seed-login-response.json \
              -H 'Content-Type: application/json' --data-binary @- "$api/auth/simple/login" \
              || true
          token=$(jq -r '.token // empty' /run/lldap-seed-login-response.json 2>/dev/null || true)
          [ -n "$token" ] && break
          [ "$attempt" = 30 ] && exit 1
          sleep 1
        done
        rm -f /run/lldap-seed-login-response.json
        create_user() {
          payload=$(jq -cn --arg id "$1" --arg email "$2" --arg display "$3" \
            '{query:"mutation($user: CreateUserInput!) { createUser(user:$user) { id } }",variables:{user:{id:$id,email:$email,displayName:$display}}}')
          printf '%s' "$payload" | curl --silent --fail -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data-binary @- "$api/api/graphql" >/dev/null
        }
        create_user retired retired@example.com "Retired User"
        create_user unmanaged unmanaged@example.com "Unmanaged User"
        jq -n \
          '{schema_version:1,users:[{declaration:"retired",username:"retired",email:"retired@example.com",salt:"seed",fingerprint:"seed",enabled:true,groups:[],removal_policy:"delete",status:"applied"}],groups:[]}' \
          > /var/lib/lldap/.osmium-identities.json
        chmod 0600 /var/lib/lldap/.osmium-identities.json
      '';
    };
  };
  testScript = ''
    start_all()
    vm.wait_for_unit("lldap.service")
    vm.wait_for_unit("osmium-lldap-reconcile.service")
    vm.succeed("systemctl is-active --quiet osmium-lldap-reconcile.service")
    vm.succeed("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=current,ou=people,dc=example,dc=com' -w ${currentPassword} -b 'dc=example,dc=com' '(uid=current)' | grep -F 'uid: current'")
    vm.succeed("! ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=admin,ou=people,dc=example,dc=com' -w ${adminPassword} -b 'dc=example,dc=com' '(uid=retired)' | grep -F 'uid: retired'")
    vm.succeed("ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=admin,ou=people,dc=example,dc=com' -w ${adminPassword} -b 'dc=example,dc=com' '(uid=unmanaged)' | grep -F 'uid: unmanaged'")
    vm.succeed("jq -e '.users | all(.declaration != \"retired\")' /var/lib/lldap/.osmium-identities.json")
    vm.shutdown()
  '';
}
