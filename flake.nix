{
  description = "Shell with glfw3";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "aarch64-darwin";
    pkgs = import nixpkgs {inherit system;};
    GREETING = "Welcome to the Nix Flake Shell!";
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        glfw3
        pkg-config
      ];
      shellHook = ''
        echo ${GREETING}
      '';
    };
  };
}
