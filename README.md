# ghostel-flake

A Nix flake for [ghostel](https://github.com/dakra/ghostel), a terminal
emulator for Emacs powered by [libghostty](https://github.com/ghostty-org/ghostty).

The packaging is adapted from the
[nixpkgs definition](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/emacs/elisp-packages/manual-packages/ghostel/package.nix)
(`emacsPackages.ghostel`), but this flake tracks upstream releases directly:
a scheduled GitHub Action watches [dakra/ghostel releases](https://github.com/dakra/ghostel/releases)
and bumps the package automatically, so new versions land here within a day
instead of waiting on the nixpkgs release cycle.

Unlike upstream's default behavior of downloading a prebuilt module from
GitHub on first use, the native module (`ghostel-module.so`) is compiled from
source by Nix and bundled into the package — nothing is fetched at runtime.

## Outputs

| Output | Description |
|---|---|
| `overlays.default` | Adds `ghostel` to every Emacs package set (`emacsPackagesFor`, `emacsWithPackages`, home-manager's `extraPackages`, …) |
| `packages.<system>.ghostel` | ghostel built against this flake's pinned nixpkgs and its default Emacs (also `default`) |
| `packages.<system>.ghostel-module` | Just the native Zig module, useful for debugging the build |

Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`, `x86_64-darwin`.

## Usage

**Prefer the overlay.** Emacs lisp packages are byte-compiled (and
native-compiled) against a specific Emacs, so ghostel should be built by the
same nixpkgs and Emacs variant as the rest of your configuration. The overlay
does exactly that; `packages.<system>.ghostel` is mainly a CI artifact and a
quick way to try the build.

Add the input to your flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ghostel = {
      url = "github:rfaulhaber/ghostel-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

> [!NOTE]
> The overlay builds ghostel with *your* nixpkgs, which therefore needs to be
> recent enough to provide `zig_0_15.fetchDeps` (nixos-unstable is fine).

### NixOS / nix-darwin

```nix
{ pkgs, inputs, ... }:
{
  nixpkgs.overlays = [ inputs.ghostel.overlays.default ];

  environment.systemPackages = [
    ((pkgs.emacsPackagesFor pkgs.emacs30-pgtk).emacsWithPackages (
      epkgs: [ epkgs.ghostel ]
    ))
  ];
}
```

### home-manager

```nix
{ pkgs, inputs, ... }:
{
  nixpkgs.overlays = [ inputs.ghostel.overlays.default ];

  programs.emacs = {
    enable = true;
    package = pkgs.emacs30-pgtk;
    extraPackages = epkgs: [ epkgs.ghostel ];
  };
}
```

### With emacs-overlay

The overlay composes with
[emacs-overlay](https://github.com/nix-community/emacs-overlay) — list it
*after* emacs-overlay so it extends the already-overridden package sets:

```nix
nixpkgs.overlays = [
  inputs.emacs-overlay.overlays.default
  inputs.ghostel.overlays.default
];
```

### Try it without installing

```nix
nix build github:rfaulhaber/ghostel-flake#ghostel
```

### In Emacs

```elisp
(use-package ghostel
  :bind ("C-x m" . ghostel))
```

Then `M-x ghostel`. See the [upstream README](https://github.com/dakra/ghostel)
for shell integration, evil support, and the rest of the feature tour.

## How the auto-update works

Three workflows keep the flake current, and none of them can push a broken
build to `main` (every change is build-gated first):

- **`update.yml`** (daily) — runs
  [`nix-update --flake --version=stable ghostel`](https://github.com/Mic92/nix-update),
  which checks the latest upstream GitHub release and rewrites `version` and
  the source hash in `package.nix`. A follow-up step repairs the
  `zig.fetchDeps` dependency hash, which nix-update cannot reach: it realizes
  the fixed-output derivation and splices in the hash Nix reports on
  mismatch. If anything changed, the package is built and the bump is
  committed to `main`.
- **`lockfile.yml`** (weekly) — `nix flake update`, build-gated the same way.
- **`ci.yml`** — builds the package on Linux and macOS for every push and
  pull request.
