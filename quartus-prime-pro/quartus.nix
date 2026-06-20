{
  stdenv,
  lib,
  unstick,
  fetchurl,
  unzip,
  withQuesta ? true,
  supportedDevices ? [
    "Agilex 3"
  ],
}:

let
  deviceIds = {
    "Agilex 3" = "agilex3";
    "Agilex 5" = "agilex5";
    "Agilex 7" = "agilex7";
    "Stratix 10" = "stratix10";
    "Arria 10" = "arria10";
    "Cyclone 10 GX" = "cyclone10gx";
  };

  supportedDeviceIds =
    assert lib.assertMsg (lib.all (
      name: lib.hasAttr name deviceIds
    ) supportedDevices) "Supported devices are: ${lib.concatStringsSep ", " (lib.attrNames deviceIds)}";
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = deviceIds.${name};
      }) supportedDevices
    );

  unsupportedDeviceIds = lib.removeAttrs deviceIds (lib.attrNames supportedDeviceIds);

  agilexFamilies = [ "Agilex 3" "Agilex 5" "Agilex 7" ];
  needsAgilexCommon = lib.any (d: lib.elem d supportedDevices) agilexFamilies;

  version = "26.1.0.110";
  baseUrl = "https://downloads.intel.com/akdlm/software/acdsinst/26.1/110/ib_installers";

  # Returns { name, src } — name tracked separately because builtins.baseNameOf on a
  # fetchurl derivation yields the hash-prefixed store basename, not the filename.
  fetchPkg = name: hash: {
    inherit name;
    src = fetchurl { url = "${baseUrl}/${name}"; inherit hash; };
  };

  # SHA-256 hashes for device component .qdz files. Add entries here for new devices.
  deviceFileHashes = {
    "agilex3" = "sha256-XSaV+NbeEYh5CMWnUqvz0cW3PaKhdzXAz8GdoA/cgi4=";
    # "agilex5" = "sha256-...";
    # "agilex7" = "sha256-...";
    # "stratix10" = "sha256-...";
    # "arria10" = "sha256-...";
    # "cyclone10gx" = "sha256-...";
  };

  installers = [
    (fetchPkg "QuartusProSetup-${version}-linux.run"
      "sha256-hE8qbaRDCvEDlpbz0Stmn9WBPgPuJr0flN3Inx03RjI=")
    (fetchPkg "QuartusProDriversSetup-${version}-linux.run"
      "sha256-HfIZAJoy33eNiIV/L8d8KDKHwVLmM05cSCnAXNcbLUY=")
  ] ++ lib.optional withQuesta
    (fetchPkg "QuestaSetup-${version}-linux.run"
      "sha256-79ZqW7CRTWqzm+VqKAJbbzJnBKfRA19uzQRIBj19aoo=");

  # All .qdz files — copied to $TEMP for the main installer.
  # agilex_common must be present in $TEMP or the main installer writes an empty quartus.cnf.
  components = [
    (fetchPkg "QuartusProSetup-part2-${version}.qdz"
      "sha256-fQDStWkoq4+CJsWefckZaofm603w217GefFyELMhUrs=")
  ]
  ++ lib.optional needsAgilexCommon
      (fetchPkg "agilex_common-${version}.qdz"
        "sha256-iP/AwGnSVpUFk3pqp6r920ldHQnmBaZY5SWf8XpPtAM=")
  ++ map (
    id:
    assert lib.assertMsg (lib.hasAttr id deviceFileHashes)
      "No hash for device '${id}' — add it to deviceFileHashes in quartus.nix";
    fetchPkg "${id}-${version}.qdz" deviceFileHashes.${id}
  ) (lib.attrValues supportedDeviceIds);

  # Device packages to extract directly via unzip (the main installer silently ignores
  # agilex_common despite it being in $TEMP, so we extract it ourselves).
  # part2 contains devices/programmer/ (pgm_dev_info.pcf etc.) which the main installer
  # also does not extract into $out/devices/ — must be unzipped explicitly.
  deviceComponents =
    [ (fetchPkg "QuartusProSetup-part2-${version}.qdz"
        "sha256-fQDStWkoq4+CJsWefckZaofm603w217GefFyELMhUrs=") ]
    ++ lib.optional needsAgilexCommon
      (fetchPkg "agilex_common-${version}.qdz"
        "sha256-iP/AwGnSVpUFk3pqp6r920ldHQnmBaZY5SWf8XpPtAM=")
    ++ map (
      id:
      assert lib.assertMsg (lib.hasAttr id deviceFileHashes)
        "No hash for device '${id}' — add it to deviceFileHashes in quartus.nix";
      fetchPkg "${id}-${version}.qdz" deviceFileHashes.${id}
    ) (lib.attrValues supportedDeviceIds);

in
stdenv.mkDerivation {
  inherit version;
  pname = "quartus-prime-pro-unwrapped";

  nativeBuildInputs = [ unstick ];

  buildCommand =
    let
      copyInstaller = pkg: ''
        cp ${pkg.src} $TEMP/${pkg.name}
        chmod u+w,+x $TEMP/${pkg.name}
        patchelf --interpreter $(cat $NIX_CC/nix-support/dynamic-linker) $TEMP/${pkg.name}
      '';
      copyComponent = pkg: "cp -n ${pkg.src} $TEMP/${pkg.name}";
      disabledComponents = [
        "quartus_help"
        "quartus_update"
        "questa_fe"
      ]
      ++ lib.optional (!withQuesta) "questa"
      ++ lib.attrValues unsupportedDeviceIds;
    in
    ''
      echo "setting up installer..."
      ${lib.concatMapStringsSep "\n" copyInstaller installers}
      ${lib.concatMapStringsSep "\n" copyComponent components}

      echo "running main installer..."
      unstick $TEMP/QuartusProSetup-${version}-linux.run \
        --disable-components ${lib.concatStringsSep "," disabledComponents} \
        --mode unattended --installdir $out --accept_eula 1

      echo "extracting device support..."
      # .qdz files are plain ZIP archives. The main installer silently ignores agilex_common,
      # so we extract device packages directly. -n skips files already installed by the main
      # installer so only genuinely missing files are added.
      # Note: unzip must NOT be in PATH when the main installer runs — if it is, the installer
      # detects it and changes behavior, writing an empty quartus.cnf. Use the full store path.
      chmod -R u+w $out/devices/
      ${lib.concatMapStringsSep "\n" (pkg: "${unzip}/bin/unzip -n ${pkg.src} -d $out") deviceComponents}

      echo "cleaning up..."
      rm -rf $out/logs
      # uninstall/ is intentionally kept: Quartus tries to create it at startup
      # and will crash if the directory doesn't exist in its (read-only) store path

      substituteInPlace $out/quartus/adm/qenv.sh \
        --replace-quiet 'grep sse /proc/cpuinfo > /dev/null 2>&1' ':'

      # The main installer leaves agilex_common_installed=0 even though we extracted
      # the files above. Fix the tracker so Quartus doesn't show the Install Devices wizard.
      substituteInPlace $out/uninstall/quartus.cnf \
        --replace-fail 'agilex_common_installed=0' 'agilex_common_installed=1'
    '';

  meta = {
    homepage = "https://fpgasoftware.intel.com";
    description = "FPGA design and simulation software (Pro Edition)";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
