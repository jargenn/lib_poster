{
  description = "Consumption-independent poster application library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs =
    inputs@{
      flake-parts,
      crane,
      rust-overlay,
      advisory-db,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        let
          rustPkgs = pkgs.extend rust-overlay.overlays.default;
          rustToolchain = rustPkgs.rust-bin.stable."1.99.0".default;
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
          src = pkgs.lib.cleanSource ./.;
          denySrc = pkgs.runCommand "lib-poster-deny-src" { } ''
            cp -r ${src} $out
            chmod -R u+w $out
            cat > $out/deny.toml <<'EOF'
            [licenses]
            allow = [
              "0BSD",
              "Apache-2.0",
              "BSD-2-Clause",
              "BSD-3-Clause",
              "BSL-1.0",
              "CDLA-Permissive-2.0",
              "ISC",
              "MIT",
              "Unicode-3.0",
              "Unlicense",
              "Zlib",
            ]
            EOF
          '';
          commonArgs = {
            inherit src;
            pname = "lib_poster";
            strictDeps = true;
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          library = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              doCheck = false;
            }
          );
        in
        {
          packages.default = library;
          checks.package = library;
          checks.clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets";
            }
          );
          checks.machete =
            pkgs.runCommand "cargo-machete"
              {
                inherit src;
                nativeBuildInputs = [ pkgs.cargo-machete ];
              }
              ''
                cd $src
                cargo-machete
                touch $out
              '';
          checks.audit = craneLib.cargoAudit {
            inherit src advisory-db;
            cargoAuditExtraArgs = "--ignore yanked --ignore RUSTSEC-2026-0235";
          };
          checks.deny = craneLib.cargoDeny {
            src = denySrc;
            pname = "lib_poster";
          };

          devShells.default = pkgs.mkShell {
            packages = [
              rustToolchain
              pkgs.cargo-nextest
              pkgs.cargo-audit
              pkgs.cargo-deny
              pkgs.cargo-machete
              pkgs.pkg-config
            ];
            RUST_BACKTRACE = 1;
          };
        };
    };
}
