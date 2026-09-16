{
  imports = [
    ./services/hello.nix
    ./services/gitea.nix
    ./services/fdroid-repository.nix
    ./services/filesystem-snapshot.nix
    ./services/opencode-server.nix
    ./compatibility.nix
  ];
}
