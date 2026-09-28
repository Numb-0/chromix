{
  description = "chromix — runtime theme switching for Nix, powered by matugen";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: rec {
      chromix = pkgs.callPackage ./nix/package.nix {};
      default = chromix;
    });

    homeManagerModules = rec {
      chromix = import ./nix/hm-module.nix self;
      default = chromix;
    };

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
