{
  description = "A very basic flake";

  nixConfig = {
    extra-substituters = [ "https://om.cachix.org" ];
    extra-trusted-public-keys = [ "om.cachix.org-1:ifal/RLZJKN4sbpScyPGqJ2+appCslzu7ZZF/C01f2Q=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane = {
      url = "github:ipetkov/crane";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    esp-dev = {
      url = "github:mirrexagon/nixpkgs-esp-dev";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    omnix = {
      url = "github:juspay/omnix";
      # We do not follow nixpkgs here, because then we can't use the omnix cache
      # inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      flake-utils,
      pre-commit-hooks,
      crane,
      rust-overlay,
      esp-dev,
      omnix,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = (import nixpkgs) {
          inherit system;
          overlays = [
            (import rust-overlay)
            esp-dev.overlays.default
            (final: prev: {
              inherit (omnix.packages.${final.system}) omnix-cli;
            })
          ];
        };
        lib = pkgs.lib;
        toolchain = pkgs.rust-bin.selectLatestNightlyWith (
          toolchain:
          toolchain.default.override (p: {
            extensions = p.extensions ++ [ "rust-src" ];
            targets = p.targets ++ [ "riscv32imac-unknown-none-elf" ];
          })
        );
        craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
        preCommitHooksLib = pre-commit-hooks.lib.${system};

        # Common arguments can be set here to avoid repeating them later
        # Note: changes here will rebuild all dependency crates
        src = craneLib.cleanCargoSource ./.;

        commonArgs = {
          inherit src;
          strictDeps = true;

          buildInputs =
            [
              # Add additional build inputs here
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              # Additional darwin specific inputs can be set here
            ];
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

      in
      rec {
        checks = {
          # Run clippy (and deny all warnings) on the workspace source,
          # again, reusing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          workspace-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          # Check formatting
          workspace-fmt = craneLib.cargoFmt {
            inherit src;
          };
        };

        devShells.default = craneLib.devShell {
          # inherit checks;

          # IDF_PATH = "${pkgs.esp-idf-esp32c6}";
          ESP_IDF_TOOLS_INSTALL_DIR = "fromenv";
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

          buildInputs = with pkgs; [
            esp-idf-esp32c6
          ];

          packages = with pkgs; [
            cargo-generate
            cargo-autoinherit
            cargo-expand
            cargo-nextest
            cargo-workspaces

            jq
            just

            omnix-cli

            ldproxy
            ccache
            libusb1
            clang
            espflash
          ];
        };
      }

    );
}
