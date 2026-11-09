{ pkgs }:
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
in {
  inherit apk;
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
}
