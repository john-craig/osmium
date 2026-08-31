{ lib }:

{
  http = { name, port, path ? "/", expectedStatus ? 200 }:
    let
      expected = toString expectedStatus;
      url = "http://127.0.0.1:${toString port}${path}";
    in
    ''
      vm.log("healthcheck: ${name}")
      vm.wait_for_open_port(${toString port})
      vm.succeed("curl --silent --show-error --output /dev/null --write-out '%{http_code}\\n' ${lib.escapeShellArg url} | grep -Fx ${lib.escapeShellArg expected}")
    '';
}
