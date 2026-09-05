{ pkgs, lib, module, microvm, healthchecks }:

let
  evaluationBase = {
    system.stateVersion = "25.05";
    services.osmium.gitea = {
      enable = true;
      admin = {
        enable = true;
        passwordFile = "/etc/gitea-admin-password";
      };
    };
  };
  evaluates = extra:
    (builtins.tryEval ((lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ module evaluationBase extra ];
    }).config.system.build.toplevel)).success;
  evaluationUser = username: {
    username = username;
    email = "${username}@example.com";
    passwordFile = "/run/${username}-password";
  };
in
assert !evaluates {
  services.osmium.gitea.users = {
    first = evaluationUser "duplicate-user";
    second = evaluationUser "duplicate-user";
  };
};
assert !evaluates {
  services.osmium.gitea.organizations.example = {
    name = "example-org";
    owner = "missing-user";
  };
};
assert !evaluates {
  services.osmium.gitea.organizations.example = {
    name = "example-org";
    owner = "admin";
    visibility = "invalid";
  };
};
assert !evaluates {
  services.osmium.gitea.users.admin = evaluationUser "admin";
};

pkgs.testers.runNixOSTest {
  name = "osmium-gitea";

  nodes.vm = {
    imports = [
      microvm.nixosModules.microvm
      module
    ];

    nixpkgs.overlays = pkgs.lib.mkForce [ ];

    microvm = {
      hypervisor = "qemu";
      interfaces = [ {
        type = "user";
        id = "gitea-test";
        mac = "02:00:00:00:00:03";
      } ];
    };

    virtualisation.graphics = false;
    virtualisation.diskSize = 4096;
    environment.systemPackages = with pkgs; [
      curl
      gitea
      git
      jq
    ];

    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "mode=755" ];
      neededForBoot = true;
    };

    fileSystems."/persistent" = {
      device = "/dev/vda";
      fsType = "ext4";
      neededForBoot = true;
    };

    services.osmium.gitea = {
      enable = true;
      hostHttpPort = 3001;
      hostSshPort = 2223;
      settings.service.DISABLE_REGISTRATION = false;
      users.project-user = {
        username = "project-user";
        email = "project-user@example.com";
        passwordFile = "/run/gitea-project-user-password";
      };
      organizations.project = {
        name = "project-org";
        owner = "project-user";
        description = "Declarative project organization";
        visibility = "private";
      };
      driftDetection = {
        enable = true;
        reportFile = "/var/lib/gitea/drift-report.json";
        persistHistory = true;
      };
      reverseConfiguration.enable = true;
      admin = {
        enable = true;
        username = "bootstrap-admin";
        email = "bootstrap-admin@example.com";
        passwordFile = "/etc/gitea-admin-password";
        rotation = {
          enable = true;
          passwordFile = "/run/gitea-admin-rotation-password";
          maxAge = 3600;
          checkInterval = 3600;
        };
      };
    };

    environment.etc."gitea-admin-password" = {
      text = "test-admin-password\n";
      mode = "0400";
      user = "gitea";
      group = "gitea";
    };
  };

  testScript = ''
    vm.start(allow_reboot=True)
    vm.wait_for_unit("gitea.service")
    vm.wait_for_unit("osmium-gitea-admin-bootstrap.service")
    ${healthchecks.http {
      name = "gitea-http-healthz";
      port = 3000;
      path = "/api/healthz";
      expectedStatus = 200;
    }}
    vm.succeed("curl --fail http://127.0.0.1:3000/api/healthz")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X POST http://127.0.0.1:3000/api/v1/user/repos -H 'Content-Type: application/json' -d '{\"name\":\"persistent\"}'")
    vm.succeed("printf 'project-user-password\\n' > /run/gitea-project-user-password")
    vm.succeed("systemctl reset-failed osmium-gitea-identities.service && systemctl start osmium-gitea-identities.service")
    vm.succeed("curl --fail --user project-user:project-user-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == false'")
    vm.succeed("curl --fail --user project-user:project-user-password http://127.0.0.1:3000/api/v1/orgs/project-org | jq -e '.username == \"project-org\" and .visibility == \"private\"'")
    vm.succeed("test -e /var/lib/gitea/.osmium-user-project-user")
    vm.succeed("printf 'project-user-rotated\\n' > /run/gitea-project-user-password && systemctl restart osmium-gitea-identities.service")
    vm.fail("curl --fail --user project-user:project-user-password http://127.0.0.1:3000/api/v1/user")
    vm.succeed("curl --fail --user project-user:project-user-rotated http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == false'")
    vm.succeed("curl --fail --user project-user:project-user-rotated http://127.0.0.1:3000/api/v1/orgs/project-org | jq -e '.username == \"project-org\"'")
    vm.succeed("printf '\\n' > /run/gitea-project-user-password")
    vm.fail("systemctl restart osmium-gitea-identities.service")
    vm.succeed("curl --fail --user project-user:project-user-rotated http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == false'")
    vm.succeed("printf 'project-user-recovered\\n' > /run/gitea-project-user-password && systemctl restart osmium-gitea-identities.service")
    vm.succeed("curl --fail --user project-user:project-user-recovered http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == false'")
    vm.succeed("runuser -u gitea -- gitea --config /var/lib/gitea/custom/conf/app.ini admin user create --username unmanaged-user --password unmanaged-password --email unmanaged@example.com --must-change-password=false")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X POST http://127.0.0.1:3000/api/v1/admin/users/bootstrap-admin/orgs -H 'Content-Type: application/json' -d '{\"username\":\"unmanaged-org\",\"description\":\"Unmanaged organization\",\"visibility\":\"private\"}'")
    vm.succeed("runuser -u gitea -- sh -c 'for i in $(seq -w 1 50); do gitea --config /var/lib/gitea/custom/conf/app.ini admin user create --username page-user-$i --password page-password --email page-$i@example.com --must-change-password=false >/dev/null; done'", timeout=60)
    vm.succeed("systemctl reset-failed osmium-gitea-identities.service && systemctl start osmium-gitea-identities.service")
    vm.succeed("curl --fail --user unmanaged-user:unmanaged-password http://127.0.0.1:3000/api/v1/user | jq -e '.login == \"unmanaged-user\" and .is_admin == false'")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/orgs/unmanaged-org | jq -e '.username == \"unmanaged-org\"'")
    vm.succeed("runuser -u gitea -- osmium-gitea-drift --json > /tmp/unmanaged-drift-report.json")
    vm.succeed("jq -e '.status == \"drift\" and any(.classifications[]; .kind == \"unmanaged\" and .username == \"unmanaged-user\") and any(.classifications[]; .kind == \"unmanaged\" and .name == \"unmanaged-org\") and any(.users[]; .username == \"page-user-50\")' /tmp/unmanaged-drift-report.json")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X POST http://127.0.0.1:3000/api/v1/admin/users/unmanaged-user/orgs -H 'Content-Type: application/json' -d '{\"username\":\"exported-org\",\"description\":\"Exported organization\",\"visibility\":\"private\"}'")
    vm.succeed("runuser -u gitea -- osmium-gitea-drift --json > /tmp/export-drift-report.json")
    vm.succeed("jq '(.organizations[] | select(.name == \"exported-org\")).owner = \"unmanaged-user\"' /tmp/export-drift-report.json > /tmp/export-input.json")
    vm.succeed("runuser -u gitea -- osmium-gitea-export --input /tmp/export-input.json --user unmanaged-user --organization exported-org --json > /tmp/export.json")
    vm.succeed("jq -e 'any(.candidates[]; .resource == \"user\" and .key == \"user_unmanaged_user\" and .username == \"unmanaged-user\" and .password_file_required == true) and any(.candidates[]; .resource == \"organization\" and .key == \"organization_exported_org\" and .owner == \"user_unmanaged_user\")' /tmp/export.json")
    vm.succeed("! grep -E -i 'unmanaged-password|password_hash|token|private_key|/run/' /tmp/export.json")
    vm.succeed("runuser -u gitea -- osmium-gitea-export --input /tmp/export-input.json --user unmanaged-user --organization exported-org --output /tmp/export.nix && runuser -u gitea -- osmium-gitea-export --input /tmp/export-input.json --user unmanaged-user --organization exported-org --output /tmp/export-repeat.nix && cmp /tmp/export.nix /tmp/export-repeat.nix")
    vm.succeed("grep -F 'builtins.throw' /tmp/export.nix")
    vm.succeed("runuser -u gitea -- osmium-gitea-export --input /tmp/export-input.json --user bootstrap-admin --json > /tmp/admin-export.json && jq -e 'any(.exclusions[]; .reason_code == \"administrator-account\" and .username == \"bootstrap-admin\") and (.candidates | length) == 0' /tmp/admin-export.json")
    vm.succeed("jq '.users += [{\"username\":\"unsafe/name\",\"email\":\"unsafe@example.com\"}] | .organizations += [{\"name\":\"ambiguous-org\",\"owner\":\"missing-owner\"}]' /tmp/export-input.json > /tmp/unsafe-export-input.json")
    vm.succeed("runuser -u gitea -- osmium-gitea-export --input /tmp/unsafe-export-input.json --json > /tmp/unsafe-export.json && jq -e 'any(.exclusions[]; .reason_code == \"unsafe-name\" and .username == \"unsafe/name\") and any(.exclusions[]; .reason_code == \"ownership-conflict\" and .name == \"ambiguous-org\")' /tmp/unsafe-export.json")
    vm.fail("runuser -u gitea -- osmium-gitea-export --input /tmp/export-input.json --adopt")
    vm.succeed("! test -e /var/lib/gitea/.osmium-adoption")
    vm.succeed("curl --fail --user unmanaged-user:unmanaged-password http://127.0.0.1:3000/api/v1/user | jq -e '.login == \"unmanaged-user\"'")
    vm.succeed("curl --fail --user unmanaged-user:unmanaged-password http://127.0.0.1:3000/api/v1/orgs/exported-org | jq -e '.username == \"exported-org\" and .description == \"Exported organization\"'")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X PATCH http://127.0.0.1:3000/api/v1/admin/users/project-user -H 'Content-Type: application/json' -d '{\"login_name\":\"project-user\",\"email\":\"changed@example.com\",\"admin\":false,\"must_change_password\":false}'")
    vm.succeed("set +e; runuser -u gitea -- osmium-gitea-drift --json --check > /tmp/changed-drift-report.json; status=$?; set -e; test $status -eq 1")
    vm.succeed("jq -e 'any(.classifications[]; .kind == \"changed\" and .resource == \"user\" and .username == \"project-user\" and any(.differences[]; .field == \"email\"))' /tmp/changed-drift-report.json")
    vm.succeed("grep -F 'unmanaged-user' /tmp/changed-drift-report.json")
    vm.succeed("! grep -E -i 'password|password_hash|token|private_key' /tmp/changed-drift-report.json")
    vm.succeed("test -e /var/lib/gitea/.osmium-drift-history && jq -e '.fingerprint and .schema_version == 1' /var/lib/gitea/.osmium-drift-history")
    vm.succeed("runuser -u gitea -- osmium-gitea-drift --json > /tmp/repeated-drift-report.json && diff -u <(jq -S 'del(.observed_at)' /tmp/changed-drift-report.json) <(jq -S 'del(.observed_at)' /tmp/repeated-drift-report.json)")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X PATCH http://127.0.0.1:3000/api/v1/admin/users/project-user -H 'Content-Type: application/json' -d '{\"login_name\":\"project-user\",\"email\":\"changed@example.com\",\"admin\":true,\"must_change_password\":false}'")
    vm.succeed("runuser -u gitea -- osmium-gitea-drift --json > /tmp/admin-conflict-report.json")
    vm.succeed("jq -e 'any(.classifications[]; .kind == \"administrator-conflict\" and .username == \"project-user\")' /tmp/admin-conflict-report.json")
    vm.succeed("curl --fail --user bootstrap-admin:test-admin-password -X PATCH http://127.0.0.1:3000/api/v1/admin/users/project-user -H 'Content-Type: application/json' -d '{\"login_name\":\"project-user\",\"email\":\"changed@example.com\",\"admin\":false,\"must_change_password\":false}'")
    vm.succeed("systemctl stop gitea.service; set +e; runuser -u gitea -- osmium-gitea-drift --json > /tmp/failure-report.json; status=$?; set -e; systemctl start gitea.service; test $status -eq 2")
    vm.succeed("jq -e '.status == \"operational-error\"' /tmp/failure-report.json")
    vm.succeed("printf 'rotated-admin-password\\n' > /run/gitea-admin-rotation-password")
    vm.succeed("systemctl restart osmium-gitea-admin-rotation.service")
    vm.fail("curl --fail --user bootstrap-admin:test-admin-password http://127.0.0.1:3000/api/v1/user")
    vm.succeed("curl --fail --user bootstrap-admin:rotated-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("rm /run/gitea-admin-rotation-password")
    vm.fail("systemctl restart osmium-gitea-admin-rotation.service", timeout=10)
    vm.succeed("curl --fail --user bootstrap-admin:rotated-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("printf 'recovered-admin-password\\n' > /run/gitea-admin-rotation-password && systemctl restart osmium-gitea-admin-rotation.service")
    vm.succeed("curl --fail --user bootstrap-admin:recovered-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.shutdown()
    vm.start()
    vm.wait_for_unit("gitea.service")
    vm.wait_for_open_port(3000)
    vm.succeed("curl --fail --user bootstrap-admin:recovered-admin-password http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == true'")
    vm.succeed("curl --fail --user bootstrap-admin:recovered-admin-password http://127.0.0.1:3000/api/v1/user/repos | jq -e 'any(.[]; .name == \"persistent\")'")
    vm.succeed("test -e /var/lib/gitea/.osmium-admin-bootstrap-complete")
    vm.succeed("curl --fail --user project-user:project-user-recovered http://127.0.0.1:3000/api/v1/user | jq -e '.is_admin == false'")
    vm.succeed("curl --fail --user project-user:project-user-recovered http://127.0.0.1:3000/api/v1/orgs/project-org | jq -e '.username == \"project-org\"'")
    vm.succeed("test \"$(stat -c %U /var/lib/gitea)\" = gitea")
  '';
}
