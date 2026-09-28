{
  description = "chromix — runtime theme switching for Nix, powered by matugen";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Only for the checks, which evaluate the module the way a user's
    # config would. Point it at your own with `follows` to skip the
    # extra download.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
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

    checks = forAllSystems (pkgs: {
      # A config with every built-in target on and both kinds of theme,
      # built all the way to an activation package.
      home-manager =
        (home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home = {
                username = "test";
                homeDirectory = "/home/test";
                stateVersion = "25.11";
              };

              programs.kitty.enable = true;
              programs.neovim.enable = true;
              gtk.enable = true;
              wayland.windowManager.hyprland = {
                enable = true;
                configType = "lua";
              };

              programs.chromix = {
                enable = true;
                themes = {
                  ocean.color = "#1e88e5";
                  ember = {
                    color = "#e53935";
                    type = "scheme-expressive";
                  };
                  test-image.image = ./tests/wall.png;
                };
                default.theme = "ocean";
                targets.morph-shell.enable = true;
              };
            }
          ];
        }).activationPackage;
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
