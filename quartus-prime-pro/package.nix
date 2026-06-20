{
  lib,
  buildFHSEnv,
  callPackage,
  makeDesktopItem,
  runtimeShell,
  runCommand,
  unstick,
  libfaketime,
  pkgsi686Linux,
  withQuesta ? true,
  supportedDevices ? [
    "Agilex 3"
  ],
  unwrapped ? callPackage ./quartus.nix { inherit unstick supportedDevices withQuesta; },
  extraProfile ? "",
}:

let
  desktopItem = makeDesktopItem {
    name = "quartus-prime-pro";
    exec = "quartus";
    icon = "quartus";
    desktopName = "Quartus Prime Pro";
    genericName = "Quartus Prime Pro";
    categories = [ "Development" ];
  };
in
buildFHSEnv rec {
  pname = "quartus-prime-pro";
  inherit (unwrapped) version;

  targetPkgs =
    pkgs: with pkgs; [
      (runCommand "ld-lsb-compat" { } (
        ''
          mkdir -p "$out/lib"
          ln -sr "${glibc}/lib/ld-linux-x86-64.so.2" "$out/lib/ld-lsb-x86-64.so.3"
        ''
        + lib.optionalString withQuesta ''
          ln -sr "${pkgsi686Linux.glibc}/lib/ld-linux.so.2" "$out/lib/ld-lsb.so.3"
        ''
      ))
      glib
      libice
      libsm
      libxau
      libxdmcp
      libxscrnsaver
      libudev0-shim
      (runCommand "libudev1-compat" { } ''
        mkdir -p $out/lib
        ln -s ${systemd}/lib/libudev.so.1 $out/lib/libudev.so.1
        ln -s ${systemd}/lib/libudev.so   $out/lib/libudev.so
      '')
      bzip2
      brotli
      expat
      dbus
      libxtst
      libxi
      dejavu_fonts
      gnumake
    ];

  multiArch = withQuesta;

  multiPkgs =
    pkgs:
    with pkgs;
    let
      freetype = pkgs.freetype.override { libpng = libpng12; };
      fontconfig = pkgs.fontconfig.override { inherit freetype; };
      libxft = pkgs.libxft.override { inherit freetype fontconfig; };
    in
    [
      libxml2
      ncurses5
      unixodbc
      libxft
      freetype
      fontconfig
      libx11
      libxext
      libxrender
      libxcrypt-legacy
    ];

  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/64x64/apps
    ln -s ${desktopItem}/share/applications/* $out/share/applications
    ln -s ${unwrapped}/quartus/adm/quartusii.png $out/share/icons/hicolor/64x64/apps/quartus.png

    progs_to_wrap=(
      "${unwrapped}"/quartus/bin/*
      "${unwrapped}"/quartus/bin64/*
      "${unwrapped}"/quartus/sopc_builder/bin/qsys-*
      "${unwrapped}"/questa_fse/bin/*
      "${unwrapped}"/questa_fse/linux_x86_64/lmutil
    )

    wrapper=$out/bin/${pname}
    progs_wrapped=()
    for prog in ''${progs_to_wrap[@]}; do
        [ -f "$prog" ] || continue
        relname="''${prog#"${unwrapped}/"}"
        bname="$(basename "$relname")"
        wrapped="$out/$relname"
        progs_wrapped+=("$wrapped")
        mkdir -p "$(dirname "$wrapped")"
        echo "#!${runtimeShell}" >> "$wrapped"
        NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=1
        case "$relname" in
            questa_fse/*)
                echo "export NIXPKGS_IS_QUESTA_WRAPPER=1" >> "$wrapped"
                NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=0
                ;;
        esac
        case "$bname" in
            jtagd|quartus_pgm|quartus)
                NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=0
                ;;
        esac
        if [ "$bname" = "jtagd" ]; then
            echo "export NIXPKGS_QUARTUS_IS_JTAGD=1" >> "$wrapped"
        fi
        echo "export NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK=$NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK" >> "$wrapped"
        echo "exec $wrapper $prog \"\$@\"" >> "$wrapped"
    done

    cd $out
    chmod +x ''${progs_wrapped[@]}
    ln --symbolic --relative --target-directory ./bin ''${progs_wrapped[@]}
  '';

  profile = ''
    if [ "$NIXPKGS_IS_QUESTA_WRAPPER" != 1 ] && [ "''${NIXPKGS_QUARTUS_IS_JTAGD:-0}" != 1 ]; then
        export LD_PRELOAD=''${LD_PRELOAD:+$LD_PRELOAD:}/usr/lib/libudev.so.0
    fi

    if [ -n "$SOURCE_DATE_EPOCH" ] && [ "$NIXPKGS_QUARTUS_REPRODUCIBLE_BUILD" = 1 ] && [ "$NIXPKGS_QUARTUS_THIS_PROG_SUPPORTS_FIXED_CLOCK" = 1 ]; then
        export LD_LIBRARY_PATH="${
          lib.makeLibraryPath [
            libfaketime
            pkgsi686Linux.libfaketime
          ]
        }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        export LD_PRELOAD=libfaketime.so.1''${LD_PRELOAD:+:$LD_PRELOAD}
        export FAKETIME_FMT="%s"
        export FAKETIME="$SOURCE_DATE_EPOCH"
    fi
  ''
  + extraProfile;

  runScript = "";

  passthru = {
    inherit unwrapped;
  };

  inherit (unwrapped) meta;
}
