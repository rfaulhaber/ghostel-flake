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
      #
      # Injecting via the manualPackages *argument* (rather than a plain
      # overrideScope attr) matters: emacs-overlay's package overlay ends with
      # `esuper.override { ... }`, which rebuilds the scope through nixpkgs'
      # makeOverridable — stored args survive that rebuild, overrideScope
      # extensions do not (the rebuilt set shadows them with nixpkgs' own,
      # older ghostel). nix-doom-emacs-unstraightened triggers exactly that
      # rebuild. manualPackages is also merged into the scope after the MELPA
      # sets, so this keeps winning if ghostel ever lands on MELPA. Keeping
      # the `esuper.override` call *inside* an overrideScope extension
      # preserves makeScope's wrapper attrs (overrideScope, callPackage) for
      # later overlays.
      overlay = final: prev: {
        emacsPackagesFor =
          emacs:
          (prev.emacsPackagesFor emacs).overrideScope (
            eself: esuper:
            esuper.override (args: {
              # args is { } on a pristine scope, hence the esuper fallback.
              manualPackages = (args.manualPackages or esuper.manualPackages) // {
                ghostel = eself.callPackage ./package.nix { };
              };
            })
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
            # Guard the manualPackages arg injection: simulate the scope
            # rebuild unstraightened/emacs-overlay perform and fail unless the
            # flake's ghostel (not nixpkgs' older one) survives it. A version
            # comparison, not a null check — nixpkgs ships its own ghostel, so
            # a regression manifests as the wrong version, not a missing attr.
            scope-rebuild-survival =
              let
                survived =
                  ((pkgs.emacsPackagesFor pkgs.emacs).overrideScope (eself: esuper: esuper.override { })).ghostel
                    or null;
                version = if survived == null then "<missing>" else survived.version;
              in
              assert pkgs.lib.assertMsg (
                version == ghostel.version
              ) "ghostel dropped by esuper.override scope rebuild: got ${version}, expected ${ghostel.version}";
              pkgs.runCommand "ghostel-scope-rebuild-survival" { } "touch $out";
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
