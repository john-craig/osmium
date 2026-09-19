{ pkgs, lib, module, microvm, opencodeNix, opencodeMcp }:

(import ./opencode-mcp-support-profile.nix {
  inherit pkgs lib module microvm opencodeNix opencodeMcp;
  reverseMode = "drift";
})
