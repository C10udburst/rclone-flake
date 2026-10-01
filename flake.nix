# flake.nix
{
  description = "Scalable and declarative NixOS module for managing Rclone mounts";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # Export custom helper functions for external consumption
      lib = import ./lib { inherit (nixpkgs) lib; };

      # NixOS Module outputs
      nixosModules = {
        default = import ./modules/rclone;
        rclone = self.nixosModules.default;
      };

      # Devshell for formatting and testing
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixpkgs-fmt
              statix
              rclone
            ];
          };
        }
      );
    };
}
