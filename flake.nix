{
  description = "Flake for ghostel, an Emacs terminal emulator powered by libghostty";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    let
      # Inject ghostel into every Emacs package set so it is available
      # regardless of which Emacs variant the consumer uses
      # (emacsWithPackages, home-manager's programs.emacs.extraPackages, ...).
      # Composes with other emacsPackagesFor overlays such as emacs-overlay.
      overlay = final: prev: {
        emacsPackagesFor =
          emacs:
          (prev.emacsPackagesFor emacs).overrideScope (
            efinal: eprev: {
              ghostel = efinal.callPackage ./package.nix { };
            }
          );
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      flake.overlays.default = overlay;

      perSystem =
        { system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
          inherit (pkgs.emacsPackages) ghostel;
        in
        {
          packages = {
            inherit ghostel;
            default = ghostel;
            # The bare native module (ghostel-module.so/.dylib), useful for
            # debugging the Zig build without pulling in melpaBuild.
            ghostel-module = ghostel.module;
          };

          checks = {
            inherit ghostel;
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
