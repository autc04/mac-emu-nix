{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    minivmac.url = "github:minivmac/minivmac";
    minivmac.flake = false;
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import a flake module
        # 1. Add foo to inputs
        # 2. Add foo as a parameter to the outputs function
        # 3. Add here: foo.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        {
          packages.default = self'.packages.minivmac;
          packages.minivmac =
            if pkgs.stdenv.isLinux then
              pkgs.stdenv.mkDerivation {
                name = "minivmac";

                src = inputs.minivmac;

                /*
                  src = pkgs.fetchurl {
                    url =
                      "https://www.gryphel.com/d/minivmac/minivmac-36.04/minivmac-36.04.src.tgz";
                    sha256 = "sha256-m3NDzsh3Ixd6ID5prTuvIPSbTo8DYZ42bEvycFFn36Q=";
                  };
                  unpackPhase = "tar xfvz $src; cd minivmac";
                */

                buildInputs = [ pkgs.xorg.libX11 ];
                nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
                patchPhase = ''
                  	sed -i '/hints->. = leftPos/d' src/OSGLUXWN.c
                  	sed -i 's/leftPos,$/0,/' src/OSGLUXWN.c
                    sed -i 's/topPos,$/0,/' src/OSGLUXWN.c
                    
                '';

                configurePhase = ''
                  $CC setup/tool.c -o ./setup_tool
                  ./setup_tool -t lx64 -ahm sunglasses | bash
                '';

                installPhase = ''
                  mkdir -p $out/bin
                  cp minivmac $out/bin
                  ln -s ${self'.packages.rom} $out/bin/vMac.ROM
                  ln -s ${self'.packages.system608}/SystemStartup.dsk $out/bin/disk1.dsk
                  wrapProgram "$out/bin/minivmac" --prefix LD_LIBRARY_PATH : ${inputs'.nixpkgs.legacyPackages.alsa-lib}/lib
                '';
              }
            else if pkgs.stdenv.isDarwin then
              pkgs.stdenv.mkDerivation {
                name = "minivmac";

                src = inputs.minivmac;
                buildInputs = [ pkgs.darwin.apple_sdk.frameworks.Cocoa ];

                configurePhase = ''
                  $CC setup/tool.c -o ./setup_tool
                  ./setup_tool -cl -t mcar -ahm sunglasses | bash
                  # Nix build uses a different `strip` command than the one supplied by Apple:
                  sed -i 's/strip -u -r/strip/' Makefile
                '';

                installPhase = ''
                  mkdir -p $out/Applications
                  cp -r minivmac.app $out/Applications
                  ln -s ${self'.packages.rom} $out/Applications/vMac.ROM
                  ln -s ${self'.packages.system608}/SystemStartup.dsk $out/Applications/disk1.dsk
                '';
              }
            else
              null;

          packages.rom = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/mihaip/infinite-mac/47d697538ba8a99bd0cf217c4dd404894c6944bb/src/Data/Mac-Plus.rom";
            sha256 = "sha256-qG1Tmqsa9jUvwFdS7C49FD+AUhmICCKEPGJ8YYQxje8=";
          };

          packages.ua608d = pkgs.stdenv.mkDerivation {
            name = "ua608d";
            src = pkgs.fetchurl {
              url = "https://www.gryphel.com/d/minivmac/extras/ua608d/ua608d-1.00.src.tgz";
              sha256 = "sha256-LWvnjDo988tldZJFfhdQcoQOo4O11wxvUBra3Wrz8Yw=";
            };
            unpackPhase = "tar xfvzi $src; cd ua608d";

            # the ua608d source archive contains a heap of header files named in MS DOS style, but no main source file.
            patchPhase = ''
              cat <<EOF >main.c
              #include <stdio.h>
              #include <string.h>
              #include <stdlib.h>
              #include <errno.h>
              #include "source/AAAATOOL.h"
              EOF
            '';
            buildPhase = ''
              $CC main.c -o ua608d
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp ua608d $out/bin
            '';
          };

          packages.system608 =
            let
              ssw1 = pkgs.fetchurl {
                url = "https://download.info.apple.com/Apple_Support_Area/Apple_Software_Updates/English-North_American/Macintosh/System/Older_System/System_6.0.x/SSW_6.0.8-1.4MB_Disk1of2.sea.bin";
                sha256 = "sha256-4YAa7yOfWnQ7DJA9UDQiz5jlE9Alpjfdi3dRIgg7Hag=";
              };
              ssw2 = pkgs.fetchurl {
                url = "https://download.info.apple.com/Apple_Support_Area/Apple_Software_Updates/English-North_American/Macintosh/System/Older_System/System_6.0.x/SSW_6.0.8-1.4MB_Disk2of2.sea.bin";
                sha256 = "sha256-pwNgazUPQh0BcmVNl7H6I/MuskmFFl+/L0wfTzE43Xg=";
              };
            in
            pkgs.runCommand "system608" { } ''
              mkdir -p $out/

              ${self'.packages.ua608d}/bin/ua608d ${ssw1} $out/SystemStartup.dsk
              ${self'.packages.ua608d}/bin/ua608d ${ssw2} $out/SystemAdditions.dsk
            '';

          packages.launchappl_minivmac =
            let
              autoquitZIP = pkgs.fetchurl {
                url = "https://www.gryphel.com/d/minivmac/extras/autoquit/autoquit-1.1.1.zip";
                sha256 = "sha256-vY9HrN9WySAMvmkPRqewdYD1vrUPkmos3wChMA7iL9M=";
              };
              autoquit = pkgs.runCommand "autoquit" { } ''
                ${pkgs.unzip}/bin/unzip -j -d $out ${autoquitZIP} '*.dsk'
                mv $out/*.dsk $out/autoquit.dsk
              '';
            in
            pkgs.runCommand "launchappl_minivmac"
              {
                shellHook = ''
                  export RETRO68_LAUNCHAPPL_MINIVMAC_PATH=${self'.packages.default}/bin/minivmac
                  export RETRO68_LAUNCHAPPL_MINIVMAC_ROM=${self'.packages.rom}
                  export RETRO68_LAUNCHAPPL_SYSTEM_IMAGE=${self'.packages.system608}/SystemStartup.dsk
                  export RETRO68_LAUNCHAPPL_AUTOQUIT_IMAGE=${autoquit}/autoquit.dsk
                '';
              }
              ''
                mkdir -p $out
              '';
          formatter = pkgs.nixfmt-rfc-style;
          devShells.default = pkgs.mkShell { buildInputs = [ self'.formatter ]; };
        };
    };
}
