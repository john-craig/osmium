{ pkgs, ... }:
let
  apocrypha = builtins.fetchTree {
    type = "github";
    owner = "john-craig";
    repo = "nixpkgs-apocrypha";
    rev = "69a881a9171a845cbd6655664246ad0f6e7725a5";
    narHash = "sha256-N2Utx6v1HZHMOcqY9k5ei2B8nuM3LxacLKbtNjoSPBI=";
  };
  workspaceModules = import (apocrypha + "/workspace-modules");
in {
  workspaces."osmium" = {
    extraModules = [
      workspaceModules.opencode-mcp
      ({ config, ... }: {
        workspace.file.".opencode/opencode.json" = builtins.toJSON {
          mcp.servers = {
            clinotes = {
              type = "local";
              command = [ "${pkgs.uv}/bin/uvx" "--from" "clinotes" "clinotes-mcp" ];
            };
            opencode = {
              type = "local";
              command = [ config.workspace.opencode.mcpServers.opencode.command ];
              environment.OPENCODE_MCP_PASSWORD_FILE = "{env:XDG_RUNTIME_DIR}/secrets/opencode/server_password";
            };
          };
        };
      })
    ];
    workspace.opencodeMcp = {
      enable = true;
      baseUrl = "https://opencode-api.laptop.chiliahedron.wtf";
      username = "opencode";
    };
    workspace.opencode.skills."project-subagent-management" = {
      source = ../skills/project-subagent-management;
    };
  };
}
