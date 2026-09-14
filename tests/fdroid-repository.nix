{ pkgs, lib, module, microvm }:

let
  androidPkgs = import pkgs.path {
    system = pkgs.system;
    config = { allowUnfree = true; android_sdk.accept_license = true; };
  };
  androidSdk = androidPkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "35" ];
    buildToolsVersions = [ "35.0.0" ];
    includeEmulator = false;
    includeNDK = false;
  };
  apk = pkgs.runCommand "osmium-test.apk" { nativeBuildInputs = [ androidSdk.androidsdk pkgs.jdk ]; } ''
    export ANDROID_HOME=${androidSdk.androidsdk}
    export PATH="$ANDROID_HOME/libexec/android-sdk/build-tools/35.0.0:$PATH"
    cat > AndroidManifest.xml <<'EOF'
    <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.osmium.test" android:versionCode="1" android:versionName="1.0">
      <application android:label="Osmium Test" android:hasCode="false" />
    </manifest>
    EOF
    aapt2 link --manifest AndroidManifest.xml --min-sdk-version 23 --target-sdk-version 35 \
      --version-code 1 --version-name 1.0 -I "$ANDROID_HOME/libexec/android-sdk/platforms/android-35/android.jar" -o unsigned.apk
    keytool -genkeypair -keystore debug.keystore -storepass android -keypass android -alias androiddebugkey \
      -dname CN=Android -keyalg RSA -validity 10000 -noprompt
    apksigner sign --ks debug.keystore --ks-pass pass:android --ks-key-alias androiddebugkey unsigned.apk
    cp unsigned.apk "$out"
  '';
  base = {
    enable = true;
    repositoryId = "runtime-repository";
    name = "Runtime F-Droid";
    description = "Runtime generated repository";
    baseUrl = "http://127.0.0.1:8080/repo";
    guestPort = 8080;
    hostPort = 38080;
    signing = { keystoreFile = "/run/fdroid/keystore"; passwordFile = "/run/fdroid/password"; keyAlias = "fdroid"; };
  artifacts.test = { packageName = "org.osmium.test"; versionCode = 1; versionName = "1.0"; path = apk; sha256 = null; };
  };
in
pkgs.testers.runNixOSTest {
  name = "osmium-fdroid-repository";
  nodes.vm = {
    imports = [ microvm.nixosModules.microvm module ];
    nixpkgs.overlays = pkgs.lib.mkForce [ ];
    system.stateVersion = "25.05";
    microvm = { hypervisor = "qemu"; interfaces = [ { type = "user"; id = "fdroid-test"; mac = "02:00:00:00:00:0c"; } ]; };
    virtualisation.graphics = false;
    virtualisation.diskSize = 2048;
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; options = [ "mode=755" ]; neededForBoot = true; };
    fileSystems."/persistent" = { device = "/dev/vda"; fsType = "ext4"; neededForBoot = true; };
    environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.fdroidserver ];
    systemd.services.fdroid-test-secret = {
      before = [ "osmium-fdroid-repository-generate.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        install -d -m 0700 /run/fdroid
        printf 'test-password\n' > /run/fdroid/password
        ${pkgs.jdk}/bin/keytool -genkeypair -keystore /run/fdroid/keystore -storepass test-password -keypass test-password -alias fdroid -dname CN=fdroid -keyalg RSA -validity 3650 -noprompt
        chmod 0400 /run/fdroid/password /run/fdroid/keystore
        chown fdroid:fdroid /run/fdroid
        chown fdroid:fdroid /run/fdroid/password /run/fdroid/keystore
      '';
    };
    services.osmium.fdroidRepository = base;
  };
  testScript = ''
    vm.start()
    vm.wait_for_unit("osmium-fdroid-repository.service")
    vm.succeed("test -e /var/lib/fdroid-repository/.ready")
    vm.succeed("curl --fail http://127.0.0.1:8080/repo/index-v1.jar -o /tmp/index-v1.jar")
    vm.succeed("curl --fail http://127.0.0.1:8080/repo/index-v2.json -o /tmp/index-v2.json")
    vm.succeed("curl --fail http://127.0.0.1:8080/repo/org.osmium.test_1.apk -o /tmp/test.apk")
    vm.succeed("cmp /tmp/test.apk ${apk}")
    vm.succeed("osmium-fdroid-repository observe --output /tmp/observed.json && osmium-fdroid-repository convert --input /tmp/observed.json --output /tmp/candidate.json")
    vm.succeed("osmium-fdroid-repository validate --input /tmp/candidate.json")
    vm.succeed("! grep -E -i 'test-password|private.key|keystorepass' /tmp/observed.json /tmp/candidate.json")
    vm.shutdown()
    vm.start()
    vm.wait_for_unit("osmium-fdroid-repository.service")
    vm.wait_for_open_port(8080)
    vm.succeed("curl --fail http://127.0.0.1:8080/repo/index-v1.jar >/tmp/index-v1-after-reboot.jar && cmp /tmp/index-v1.jar /tmp/index-v1-after-reboot.jar")
    vm.succeed("curl --fail http://127.0.0.1:8080/repo/org.osmium.test_1.apk -o /tmp/test-after.apk && cmp /tmp/test.apk /tmp/test-after.apk")
  '';
}
