{ pkgs, module, microvm, mode }:

let
  adminPassword = "reverse-admin-password";
  userPassword = "reverse-user-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-lldap-${mode}-reverse-configuration";

  nodes = {
    source = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; vcpu = 2; mem = 768; interfaces = [{ type = "user"; id = "lldap-r-src"; mac = "02:00:00:00:00:71"; }]; };
      services.osmium.lldap = {
        enable = true;
        reverseConfiguration.enable = true;
        baseDn = "dc=example,dc=com";
        httpUrl = "https://lldap.example.invalid";
        hostLdapPort = 3893;
        hostHttpPort = null;
        admin = { username = "admin"; email = "admin@example.com"; passwordFile = "/etc/lldap-admin-password"; };
        jwtSecretFile = "/etc/lldap-jwt-secret";
        keySeedFile = "/etc/lldap-key-seed";
        ldaps.enable = false;
        users.declared = { username = "declared"; email = "declared@example.com"; displayName = "Declared User"; passwordFile = "/etc/declared-password"; };
        groups.declared = { displayName = "declared-group"; users = [ "declared" ]; };
      };
      environment.etc."lldap-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
      environment.etc."lldap-jwt-secret" = { text = "reverse-jwt-secret\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
      environment.etc."lldap-key-seed" = { text = "reverse-key-seed\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
      environment.etc."declared-password" = { text = "declared-password\n"; mode = "0400"; };
      environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.lldap pkgs.openldap ];
    };

    replay = {
      imports = [ microvm.nixosModules.microvm module ];
      nixpkgs.overlays = pkgs.lib.mkForce [ ];
      system.stateVersion = "25.05";
      microvm = { hypervisor = "qemu"; vcpu = 2; mem = 768; interfaces = [{ type = "user"; id = "lldap-r-replay"; mac = "02:00:00:00:00:72"; }]; };
      services.osmium.lldap = {
        enable = true;
        baseDn = "dc=example,dc=com";
        httpUrl = "https://lldap.example.invalid";
        hostLdapPort = 3894;
        hostHttpPort = null;
        admin = { username = "admin"; email = "admin@example.com"; passwordFile = "/etc/lldap-admin-password"; };
        jwtSecretFile = "/etc/lldap-jwt-secret";
        keySeedFile = "/etc/lldap-key-seed";
        ldaps.enable = false;
      };
      environment.etc."lldap-admin-password" = { text = "${adminPassword}\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
      environment.etc."lldap-jwt-secret" = { text = "reverse-jwt-secret\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
      environment.etc."lldap-key-seed" = { text = "reverse-key-seed\n"; mode = "0400"; user = "lldap"; group = "lldap"; };
      environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.openldap ];
    };
  };

  testScript = ''
    start_all()
    source.wait_for_unit("lldap.service")
    source.wait_for_unit("osmium-lldap-reconcile.service")
    replay.wait_for_unit("lldap.service")
    source.succeed("osmium-lldap-observe --output /tmp/before.json")
    source.succeed("osmium-lldap-candidate --input /tmp/before.json > /tmp/before-candidate.json")
    source.succeed("ledger_before=$(sha256sum /var/lib/lldap/.osmium-identities.json | cut -d' ' -f1); token=$(curl --fail --silent -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"${adminPassword}\"}' http://127.0.0.1:17170/auth/simple/login | jq -r .token); printf '%s' '{\"query\":\"mutation($name: String!) { createGroup(name:$name) { id } }\",\"variables\":{\"name\":\"runtime-drift-group\"}}' | curl --fail --silent -H \"Authorization: Bearer $token\" -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:17170/api/graphql | jq -e '.data.createGroup.id != null'; osmium-lldap-observe --output /tmp/after.json; osmium-lldap-drift --observation /tmp/after.json --declared <(jq '.declaration.services.osmium.lldap' /tmp/before-candidate.json) --output /tmp/drift.json; osmium-lldap-candidate --input /tmp/after.json > /tmp/drift-candidate.json; test \"$(sha256sum /var/lib/lldap/.osmium-identities.json | cut -d' ' -f1)\" = \"$ledger_before\"; jq -e '.changes | any(.[]; .resource == \"group\" and .name == \"runtime-drift-group\" and .kind == \"unmanaged\")' /tmp/drift.json; jq -e '.candidate.groups | any(.displayName == \"runtime-drift-group\")' /tmp/drift.json; ! grep -E -i '${adminPassword}|${userPassword}|reverse-jwt-secret|reverse-key-seed' /tmp/before.json /tmp/after.json /tmp/drift.json /tmp/drift-candidate.json")
    source.succeed("token=$(curl --fail --silent -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"${adminPassword}\"}' http://127.0.0.1:17170/auth/simple/login | jq -r .token); printf '%s' '{\"query\":\"mutation($name: String!) { createGroup(name:$name) { id } }\",\"variables\":{\"name\":\"captured-group\"}}' | curl --fail --silent -H \"Authorization: Bearer $token\" -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:17170/api/graphql | jq -e '.data.createGroup.id != null'; printf '%s' '{\"query\":\"mutation($user: CreateUserInput!) { createUser(user:$user) { id } }\",\"variables\":{\"user\":{\"id\":\"captured-user\",\"email\":\"captured@example.com\",\"displayName\":\"Captured User\"}}}' | curl --fail --silent -H \"Authorization: Bearer $token\" -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:17170/api/graphql | jq -e '.data.createUser.id == \"captured-user\"'; osmium-lldap-capture --output /tmp/capture.json; osmium-lldap-candidate --input /tmp/capture.json > /tmp/capture-candidate.json; jq -e '.source.origin == \"live-capture\" and (.users | any(.username == \"captured-user\")) and (.groups | any(.displayName == \"captured-group\")) and .complete == false' /tmp/capture.json; jq -e '.declaration.services.osmium.lldap.groups.group_captured_group.displayName == \"captured-group\" and .declaration.services.osmium.lldap.users.user_captured_user.passwordFile.unresolved == true' /tmp/capture-candidate.json; ! grep -E -i '${adminPassword}|${userPassword}|reverse-jwt-secret|reverse-key-seed' /tmp/capture.json /tmp/capture-candidate.json")
    candidate_b64 = source.succeed("base64 -w0 /tmp/${if mode == "drift" then "drift" else "capture"}-candidate.json").strip()
    replay.succeed("printf '%s' '" + candidate_b64 + "' | base64 -d > /tmp/candidate.json")
    replay.succeed("jq -r '.declaration.services.osmium.lldap.groups | to_entries[] | .value.displayName' /tmp/candidate.json | grep -E 'runtime-drift-group|captured-group' > /tmp/replay-group; group=$(cat /tmp/replay-group); token=$(curl --fail --silent -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"${adminPassword}\"}' http://127.0.0.1:17170/auth/simple/login | jq -r .token); jq -cn --arg name \"$group\" '{query:\"mutation($name: String!) { createGroup(name:$name) { id } }\",variables:{name:$name}}' | curl --fail --silent -H \"Authorization: Bearer $token\" -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:17170/api/graphql | jq -e '.data.createGroup.id != null'")
    replay.succeed("group=$(cat /tmp/replay-group); ldapsearch -x -H ldap://127.0.0.1:3890 -D 'uid=admin,ou=people,dc=example,dc=com' -w ${adminPassword} -b 'cn='\"$group\"',ou=groups,dc=example,dc=com' -s base '(objectClass=*)' | grep -F \"cn: $group\"")
    source.shutdown()
    replay.shutdown()
  '';
}
