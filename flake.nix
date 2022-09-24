{
  description = "Raspberry Pi Pico (RP2040) support for Drone, an Embedded Operating System.";

  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/nixos-22.05";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, utils, nixpkgs, fenix }:
    utils.lib.eachDefaultSystem (system:
      let
        buildTarget = "thumbv6m-none-eabi";
        rustFlags = ''--cfg drone_cortexm="cortexm0plus_r0p1"'';
        rustChannel = {
          channel = "nightly";
          date = "2022-09-18";
          sha256 = "eYFYpSF2PBUJVzZGZrdtDMpVfHkypzTMLWotdEVq7eM=";
        };

        pkgs = nixpkgs.legacyPackages.${system};
        rustToolchain = with fenix.packages.${system}; combine
          ((with toolchainOf rustChannel; [
            rustc
            cargo
            clippy
            rustfmt
            rust-src
          ]) ++ (with targets.${buildTarget}.toolchainOf rustChannel; [
            rust-std
          ]));
        rustAnalyzer = fenix.packages.${system}.rust-analyzer;

        crossEnv = {
          CARGO_BUILD_TARGET = buildTarget;
        };
        nativeEnv = {
          CARGO_BUILD_TARGET = pkgs.stdenv.targetPlatform.config;
        };

        cargoRdme = (
          pkgs.rustPlatform.buildRustPackage rec {
            name = "cargo-rdme";
            src = pkgs.fetchFromGitHub {
              owner = "orium";
              repo = name;
              rev = "v0.7.2";
              sha256 = "sha256-jMFBdfSd3hz3YdI1TZjJFJGzcSIrry+4zgUgV51MlZ4=";
            };
            cargoSha256 = "sha256-2swM8GLyYDyrSXzaKNbG4u1//X35Oa4SCKPqiMVhwxY=";
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl ];
            doCheck = false;
          });

        checkAll = pkgs.writeShellScriptBin "check-all" ''
          set -ex
          cargo rdme --check
          cargo fmt --all --check
          cargo clippy --workspace --features all -- --deny warnings
          nix develop '.#native' -c cargo test --workspace --features all,std
          RUSTDOCFLAGS='-D warnings' cargo doc --no-deps --package drone-raspberrypi-pico --features all
        '';

        updateVersions = pkgs.writeShellScriptBin "update-versions" ''
          sed -i "s/\(api\.drone-os\.com\/drone-raspberrypi-pico\/\)[0-9]\+\(\.[0-9]\+\)\+/\1$(echo $1 | sed 's/\(.*\)\.[0-9]\+/\1/')/" \
            Cargo.toml src/lib.rs
          sed -i "/\[.*\]/h;/version = \".*\"/{x;s/\[package\]/version = \"$1\"/;t;x}" \
            Cargo.toml
          sed -i "/\[.*\]/h;/version = \".*\"/{x;s/\[.*drone-core\]/version = \"$2\"/;t;x}" \
            Cargo.toml src/pieces/*/Cargo.toml src/pieces/Cargo.toml src/periph/*/Cargo.toml
          sed -i "/\[.*\]/h;/version = \".*\"/{x;s/\[.*drone-cortexm\]/version = \"$3\"/;t;x}" \
            Cargo.toml src/pieces/*/Cargo.toml src/pieces/Cargo.toml src/periph/*/Cargo.toml
          sed -i "s/\(drone-raspberrypi-pico.*\)version = \"[^\"]\+\"/\1version = \"$1\"/" \
            src/lib.rs
        '';

        publishCrates = pkgs.writeShellScriptBin "publish-crates" ''
          cargo publish --features all
        '';

        publishDocs = pkgs.writeShellScriptBin "publish-docs" ''
          dir=$(sed -n 's/.*api\.drone-os\.com\/\(.*\/.*\)\/.*\/"/\1/;T;p' Cargo.toml) \
            && rm -rf ../drone-api/$dir \
            && cp -rT target/doc ../drone-api/$dir \
            && cp -rT target/$CARGO_BUILD_TARGET/doc ../drone-api/$dir \
            && echo '<!DOCTYPE html><meta http-equiv="refresh" content="0; URL=./drone_raspberrypi_pico">' > ../drone-api/$dir/index.html \
            && cd ../drone-api && git add $dir && git commit -m "Docs for $dir"
        '';

        mkShell = extraEnv: pkgs.mkShell ({
          nativeBuildInputs = [
            rustToolchain
            rustAnalyzer
            cargoRdme
            checkAll
            updateVersions
            publishCrates
            publishDocs
          ];
          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          CARGO_BUILD_RUSTFLAGS = rustFlags;
        } // extraEnv);
      in
      {
        devShells = rec {
          cross = mkShell (crossEnv // { name = "cross"; });
          native = mkShell (nativeEnv // { name = "native"; });
          default = cross;
        };
      }
    );
}