{ lib, buildNpmPackage, nodejs_22, src }:

buildNpmPackage rec {
  pname = "opencode-mcp";
  version = "3.0.0";
  inherit src;

  nodejs = nodejs_22;
  npmDepsHash = "sha256-XvM9goS+S+L4Y5DM6KAuBSw3WMqy7nfFyN2RWZzVKqQ=";
  npmBuildScript = "build";

  meta = {
    description = "MCP server for coordinating OpenCode sessions";
    homepage = "https://github.com/AlaeddineMessadi/opencode-mcp";
    license = lib.licenses.mit;
    mainProgram = "opencode-mcp";
  };

  passthru.sourceRevision = "6f1f62fd6c151377e09f4fe95bed58eb48c6196b";
}
