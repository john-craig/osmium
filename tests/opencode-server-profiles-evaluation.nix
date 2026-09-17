{ pkgs, lib, module, microvm, opencodeNix }:

let
  skill = pkgs.writeText "osmium-evaluation-skill.md" "evaluation skill";
  base = {
    system.stateVersion = "25.05";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
    nix.settings.trusted-users = [ "root" "opencode" ];
    microvm.guest.enable = false;
    nixpkgs.overlays = [ opencodeNix.overlays.default ];
    services.osmium.opencodeServer = {
      enable = true;
      credentials.serverEnvironmentFile = "server.env";
      credentials.providerAuthFile = "auth.json";
      settings = {
        model = "local/mock";
        provider.local = {
          npm = "@ai-sdk/openai-compatible";
          name = "Local mock provider";
          options.baseURL = "http://127.0.0.1:18080/v1";
          models.mock = { name = "Mock"; };
        };
      };
    };
  };
  evaluates = extra:
    (builtins.tryEval ((lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ microvm.nixosModules.microvm module base extra ];
    }).config.system.build.toplevel)).success;
in
assert evaluates {
  services.osmium.opencodeServer.profiles.facts = {
    model = "local/mock";
    rules = [ "first" "second" ];
  };
};
assert !evaluates {
  services.osmium.opencodeServer.settings.agent."some-agent" = { model = "local/mock"; };
  services.osmium.opencodeServer.profiles.facts.model = "local/mock";
};
assert !evaluates {
  services.osmium.opencodeServer.profiles."bad/name".model = "local/mock";
};
assert !evaluates {
  services.osmium.opencodeServer.profiles.facts = { model = "local/mock"; skills = [ "missing" ]; };
};
assert !evaluates {
  services.osmium.opencodeServer.mcpServers.facts.type = "local";
  services.osmium.opencodeServer.mcpServers.facts.url = "https://example.invalid/mcp";
};
assert !evaluates {
  services.osmium.opencodeServer.mcpServers.facts.type = "remote";
  services.osmium.opencodeServer.mcpServers.facts.url = null;
};
assert !evaluates {
  services.osmium.opencodeServer.mcpServers.facts = { type = "local"; command = [ "true" ]; };
  services.osmium.opencodeServer.settings.mcp.facts = { type = "local"; command = [ "true" ]; };
  services.osmium.opencodeServer.profiles.facts = { model = "local/mock"; mcpServers = [ "facts" ]; };
};
assert !evaluates {
  services.osmium.opencodeServer.skills.shared.path = skill;
  services.osmium.opencodeServer.settings.skills.paths = [ "/duplicate" ];
  services.osmium.opencodeServer.profiles.facts.model = "local/mock";
};
assert !evaluates {
  services.osmium.opencodeServer.mcpServers.facts = { type = "local"; command = [ "true" ]; };
  services.osmium.opencodeServer.profiles.facts = {
    model = "local/mock";
    mcpServers = [ "facts" ];
    permissions."facts_*" = "allow";
  };
};
pkgs.runCommand "opencode-server-profiles-evaluation" { } ''
  touch $out
''
