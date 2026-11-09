{
  imports = [
    ./services/hello.nix
    ./services/gitea.nix
    ./services/gotify.nix
    ./services/fdroid-repository.nix
    ./services/filesystem-snapshot.nix
    ./services/opencode-server.nix
    ./services/keycloak.nix
    ./services/lldap.nix
    ./services/authelia.nix
    ./services/traefik.nix
    ./compatibility.nix
  ];
}
