{ pkgs, lib, module, microvm, opencodeNix }:

let
  keycloakAdminPassword = "keycloak-admin-password";
  databasePassword = "keycloak-database-password";
  clientSecret = "opencode-keycloak-client-secret";
  cookieSecret = "0123456789abcdef0123456789abcdef";
  serverPassword = "opencode-server-password";
  browserPassword = "opencode-browser-password";
in
pkgs.testers.runNixOSTest {
  name = "osmium-keycloak-sso-opencode";

  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = lib.mkForce [ opencodeNix.overlays.default ];
    system.stateVersion = "25.05";
    boot.loader.grub.devices = [ "/dev/vda" ];
    virtualisation.memorySize = 4096;
    microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 3072;
      interfaces = [{ type = "user"; id = "kcopencode"; mac = "02:00:00:00:00:71"; }];
    };
    microvm.shares = lib.mkForce [ ];
    microvm.guest.enable = false;
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
      clients.opencode = {
        realm = "example";
        clientId = "opencode";
        public = false;
        secretFile = "/etc/opencode-keycloak-client-secret";
        flows = [ "authorization-code" "password" ];
        scopes = [ "profile" "email" ];
        redirectUris = [ "http://localhost:4097/oauth2/callback" ];
      };
      users.alice = {
        realm = "example";
        username = "alice";
        email = "alice@example.invalid";
        passwordFile = "/etc/opencode-browser-password";
      };
      users.bob = {
        realm = "example";
        username = "bob";
        email = "bob@example.invalid";
        passwordFile = "/etc/opencode-browser-password";
      };
    };

    services.osmium.opencodeServer = {
      enable = true;
      hostPort = 4096;
      credentials = {
        hostDirectory = "/tmp/shared";
        guestDirectory = "/tmp/shared";
        serverEnvironmentFile = "server.env";
        providerAuthFile = "auth.json";
      };
      settings = {
        model = "local/mock";
        provider.local = {
          npm = "@ai-sdk/openai-compatible";
          name = "Local mock provider";
          options.baseURL = "http://127.0.0.1:18080/v1";
          models.mock = { name = "Mock"; };
        };
      };
      sso = {
        enable = true;
        keycloak = { realm = "example"; client = "opencode"; };
        callbackUrl = "http://localhost:4097/oauth2/callback";
        clientSecretFile = "/etc/opencode-keycloak-client-secret";
        cookieSecretFile = "/etc/opencode-cookie-secret";
        browserPort = 4097;
        hostBrowserPort = 4097;
        machinePort = 4098;
        hostMachinePort = 4098;
        allowedEmails = [ "alice@example.invalid" ];
      };
    };
    systemd.services.home-manager-opencode.requires = lib.mkForce [ ];
    systemd.services.home-manager-opencode.after = lib.mkForce [ ];

    environment.etc."keycloak-admin-password" = { text = "${keycloakAdminPassword}\n"; mode = "0400"; };
    environment.etc."keycloak-database-password" = { text = "${databasePassword}\n"; mode = "0400"; };
    environment.etc."opencode-keycloak-client-secret" = { text = "${clientSecret}\n"; mode = "0400"; };
    environment.etc."opencode-cookie-secret" = { text = "${cookieSecret}\n"; mode = "0400"; user = "oauth2-proxy"; group = "oauth2-proxy"; };
    environment.etc."opencode-browser-password" = { text = "${browserPassword}\n"; mode = "0400"; };
    environment.systemPackages = with pkgs; [ curl jq ];
  };

  testScript = ''
    from pathlib import Path
    credentials = Path(vm.shared_dir)
    credentials.mkdir(parents=True, exist_ok=True)
    (credentials / "server.env").write_text("OPENCODE_SERVER_USERNAME=opencode\nOPENCODE_SERVER_PASSWORD=${serverPassword}\n")
    (credentials / "auth.json").write_text('{"local":{"type":"api","key":"provider-token"}}')
    for path in credentials.iterdir():
        path.chmod(0o444)
    start_all()
    vm.wait_for_unit("keycloak.service")
    vm.wait_for_unit("osmium-keycloak-reconcile.service")
    vm.succeed("systemd-run --unit=osmium-test-nix-daemon --service-type=simple nix-daemon --daemon")
    vm.succeed("systemctl start home-manager-opencode.service")
    vm.succeed("systemctl start osmium-opencode-ready.service")
    vm.wait_for_unit("osmium-opencode-ready.service")
    vm.wait_for_unit("oauth2-proxy.service")
    vm.succeed("systemctl start osmium-opencode-sso-config.service")
    vm.wait_for_unit("osmium-opencode-sso-config.service")
    vm.succeed("systemctl start nginx.service")
    vm.wait_for_unit("nginx.service")
    vm.wait_for_open_port(4097)
    vm.wait_for_open_port(4098)

    # Machine traffic stays on the separate Basic-auth endpoint and never redirects.
    vm.succeed("curl --fail --silent -u opencode:${serverPassword} http://127.0.0.1:4098/global/health")
    vm.fail("curl --fail --silent -u opencode:stale-password http://127.0.0.1:4098/global/health")
    vm.fail("curl --fail --silent http://127.0.0.1:4098/global/health")

    # Follow the live Keycloak authorization-code form and redirects.
    vm.succeed("rm -f /tmp/opencode.cookies; curl --silent --show-error -L -c /tmp/opencode.cookies -b /tmp/opencode.cookies http://localhost:4097/oauth2/start?rd=/global/health -o /tmp/opencode-login.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/opencode-login.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); test -n \"$action\"; curl --silent --show-error -L -c /tmp/opencode.cookies -b /tmp/opencode.cookies --data-urlencode username=alice --data-urlencode password=${browserPassword} \"$action\" -o /tmp/opencode-after-login.html; curl --fail --silent --show-error -b /tmp/opencode.cookies http://localhost:4097/global/health")
    vm.succeed("rm -f /tmp/opencode-denied.cookies; curl --silent --show-error -L -c /tmp/opencode-denied.cookies -b /tmp/opencode-denied.cookies http://localhost:4097/oauth2/start?rd=/global/health -o /tmp/opencode-denied.html; action=$(grep -o 'action=\"[^\"]*\"' /tmp/opencode-denied.html | head -n 1 | cut -d '\"' -f 2 | sed 's/&amp;/\\&/g'); curl --silent --show-error -L -c /tmp/opencode-denied.cookies -b /tmp/opencode-denied.cookies --data-urlencode username=bob --data-urlencode password=${browserPassword} \"$action\" -o /tmp/opencode-denied-result.html; status=$(curl --silent --output /dev/null --write-out '%{http_code}' -b /tmp/opencode-denied.cookies http://localhost:4097/global/health); test \"$status\" = 302 || test \"$status\" = 401 || test \"$status\" = 403")

    # Replacing the OpenCode credential invalidates the old browser-injected Basic credential.
    (credentials / "server.env").chmod(0o644)
    (credentials / "server.env").write_text("OPENCODE_SERVER_USERNAME=opencode\nOPENCODE_SERVER_PASSWORD=rotated-opencode-password\n")
    (credentials / "server.env").chmod(0o444)
    vm.succeed("systemctl start osmium-opencode-reconcile.service; systemctl restart osmium-opencode-sso-reload.service")
    vm.wait_for_open_port(4096)
    vm.fail("curl --fail --silent -u opencode:${serverPassword} http://127.0.0.1:4098/global/health")
    vm.succeed("curl --fail --silent -u opencode:rotated-opencode-password http://127.0.0.1:4098/global/health")
    (credentials / "server.env").chmod(0o644)
    (credentials / "server.env").write_text("invalid\n")
    (credentials / "server.env").chmod(0o444)
    vm.succeed("! systemctl start osmium-opencode-reconcile.service; ! systemctl start osmium-opencode-sso-reload.service; systemctl is-failed --quiet osmium-opencode-reconcile.service")
  '';
}
