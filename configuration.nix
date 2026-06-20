{ config, lib, pkgs, ... }:

let
  impermanence = builtins.fetchTarball "https://github.com/nix-community/impermanence/archive/master.tar.gz";
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
  nur-source = builtins.fetchTarball "https://github.com/nix-community/NUR/archive/main.tar.gz";
  plasma-manager = builtins.fetchTarball "https://github.com/nix-community/plasma-manager/archive/trunk.tar.gz";
  nixos-hardware = builtins.fetchTarball "https://github.com/NixOS/nixos-hardware/archive/master.tar.gz";
in
{
  imports =
    [
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
      "${home-manager}/nixos"
      "${nixos-hardware}/lenovo/legion/16aph8/default.nix"
    ];

  nixpkgs.overlays = [
    (final: prev: {
      nur = import nur-source { pkgs = prev; };
      quartus-prime-pro = prev.callPackage ./quartus-prime-pro/package.nix { };
    })
  ];
  nixpkgs.config.allowUnfree = true;
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;


  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    "btusb.enable_autosuspend=n"
    "nvme_core.default_ps_max_latency_us=0"
  ];

  # Impermanence and roll back
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    after = [ "dev-disk-by\\x2duuid-e11859a0\\x2d2ba3\\x2d4876\\x2da482\\x2d0805706c2527.device" ];
    requires = [ "dev-disk-by\\x2duuid-e11859a0\\x2d2ba3\\x2d4876\\x2da482\\x2d0805706c2527.device" ];
    before = [ "sysroot.mount" ]; # Run BEFORE the root filesystem is mounted
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvolid=5 /dev/disk/by-uuid/e11859a0-2ba3-4876-a482-0805706c2527 /btrfs_tmp
      if [[ -e /btrfs_tmp/root ]]; then
          mkdir -p /btrfs_tmp/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
          mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
      fi

      delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      # Optional: Clean up old roots older than 30 days to save space.
      # Note: rm -rf does NOT work on BTRFS subvolumes; use the function above.
      for old in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mindepth 1 -mtime +30); do
          delete_subvolume_recursively "$old"
      done

      if [[ ! -e /btrfs_tmp/root-blank ]]; then
          echo "ERROR: /btrfs_tmp/root-blank subvolume not found — cannot rollback!" >&2
          umount /btrfs_tmp
          exit 1
      fi

      btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
      umount /btrfs_tmp
    '';
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      "/etc/nixos"
      "/var/lib/fwupd"
      { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
    ];
    files = [
      "/etc/machine-id"
      { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
      "/etc/nixos-passwords/j-nac_hash.txt"
    ];
    users.j-nac = {
      directories = [
        "Downloads"
        "Music"
        "Pictures"
        "Documents"
        "Videos"
        "Virtual Machines"
        "GitHub"
        "OneDrive"
        ".nixos-config"
        { directory = ".gnupg"; mode = "0700"; }
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".nixops"; mode = "0700"; }
        { directory = ".local/share/keyrings"; mode = "0700"; }
        { directory = ".local/share/kwalletd"; mode = "0700"; }
        ".local/share/direnv"
        ".mozilla/firefox/default"
        ".cache/mozilla"
        ".cache/p10k"
        ".config/onedrive"
        ".config/discord"
        ".config/Slack"
        ".config/gh"
        ".config/obsidian"
        ".config/kicad"
        ".config/spotify"
        ".local/share/Steam"
        ".steam"
        ".local/share/containers"
        ".local/share/kicad"
        ".claude"
        { directory = ".rustup"; user = "j-nac"; group = "users"; mode = "0755"; }
        { directory = ".cargo"; user = "j-nac"; group = "users"; mode = "0755"; }
        ".local/share/PrismLauncher"
        ".local/share/dolphin"
        ".local/share/baloo"
        ".local/state"
        ".config/keepassxc"
        ".altera.quartus"
      ];
      files = [
        ".screenrc"
        ".p10k.zsh"
        ".config/dolphinrc"
        ".config/kdeglobals"
        ".config/mimeapps.list"
        ".local/share/recently-used.xbel"
        ".local/share/user-places.xbel"
        ".config/kwalletrc"
        ".config/plasmashellrc"
        ".config/kwinrc"
        ".config/kwinoutputconfig.json"
        ".config/plasma-org.kde.plasma.desktop-appletsrc"
      ];
    };
  };

  # Hibernation
  boot.resumeDevice = "/dev/nvme0n1p2";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "nixos";

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.printing.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.libinput.enable = true;

  # Intel/Altera USB-Blaster (incl. Terasic DE23-Lite USB-Blaster III, 09fb:6022).
  # MODE="0666" is applied by udev itself on every add event (coldplug at boot or hotplug),
  # independent of any login session, so jtagd can always claim the cable read-write and
  # Quartus shows "DE23-Lite [USB-1]" instead of "USB-Blaster variant [1-1-iface0]".
  # (TAG+="uaccess" was tried first but is unreliable here: logind doesn't grant the ACL
  # at boot/hotplug because the graphical session isn't the seat0 session.)
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="09fb", MODE="0666"
  '';

  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;
  hardware.enableAllFirmware = true;
  hardware.nvidia.powerManagement.enable = true;

  fonts.packages = with pkgs; [
    vista-fonts
  ];

  users.mutableUsers = false;
  users.users.j-nac = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "podman" "libvirtd" ];
    shell = pkgs.zsh;
    # mkpasswd -m sha-512 > j-nac_hash.txt
    hashedPasswordFile = "/persist/etc/nixos-passwords/j-nac_hash.txt";
  };

  home-manager.users.j-nac = { pkgs, ... }: {
    imports = [
      "${plasma-manager}/modules"
    ];
    home.packages = with pkgs; [
      onedrive
      keepassxc
      discord
      slack
      ghidra-bin
      gh
      meslo-lgs-nf
      claude-code
      python314
      texliveFull
      ruby
      binutils
      jekyll
      gnumake
      gcc
      gdb
      go
      gef
      wireshark
      nmap
      burpsuite
      uv
      veracrypt
      audacity
      clamav
      clang-tools
      cmake
      kdePackages.qrca
      rustup
      rpi-imager
      ruff
      nodejs_24
      anki-bin
      obsidian
      godot
      prismlauncher
      verilator
      cinny-desktop
      ltspice
      killall
      kicad
      spotify
      quartus-prime-pro
    ];
    programs = {
      zsh = {
        enable = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        oh-my-zsh = {
          enable = true;
          theme = "robbyrussell";
          plugins = [ "git" ];
        };

        plugins = [{
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }];
        initContent = ''
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
        '';
      };
      firefox = {
        enable = true;
        nativeMessagingHosts = [ pkgs.kdePackages.plasma-browser-integration ];
        profiles.default = {
          name = "default";
          path = "default";
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            plasma-integration
          ];
        };
        configPath = ".mozilla/firefox";
      };
      vscode = {
        enable = true;
        profiles.default.userSettings = {
          "editor.fontFamily" = "'MesloLGS NF', monospace";
          "workbench.iconTheme" = "material-icon-theme";
          "git.enableSmartCommit" = true;
          "editor.wordWrap" = "bounded";
          "C_Cpp.intelliSenseEngine" = "disabled";
          "git.confirmSync" = false;
          "git.autofetch" = true;
          "[python]" = {
            "editor.defaultFormatter" = "charliermarsh.ruff";
            "editor.formatOnSave" = true;
            "editor.codeActionsOnSave" = {
              "source.fixAll" = "explicit";
              "source.organizeImports" = "explicit";
            };
          };
          # "python.analysis.typeCheckingMode" = "strict";
          "[rust]" = {
            "editor.defaultFormatter" = "rust-lang.rust-analyzer";
            "editor.formatOnSave" = true;
          };
          "[markdown]" = {
            "editor.defaultFormatter" = "davidanson.vscode-markdownlint";
            "editor.formatOnSave" = true;
            "editor.codeActionsOnSave" = {
              "source.fixAll.markdownlint" = "explicit";
            };
          };
          "ruff.organizeImports" = true;
          "errorLens.enabledDiagnosticLevels" = [
            "error"
            "warning"
          ];
          "rust-analyzer.check.command" = "clippy";
          "rust-analyzer.checkOnSave.enable" = false;
          "chat.disableAIFeatures" = true;
        };
        profiles.default.extensions = with pkgs.vscode-extensions; [
          ms-python.python
          ms-vscode.cpptools
          ritwickdey.liveserver
          eamodio.gitlens
          pkief.material-icon-theme
          ms-vscode-remote.remote-ssh
          golang.go
          streetsidesoftware.code-spell-checker
          donjayamanne.githistory
          llvm-vs-code-extensions.vscode-clangd
          ms-vscode.hexeditor
          james-yu.latex-workshop
          yzhang.markdown-all-in-one
          davidanson.vscode-markdownlint
          zxh404.vscode-proto3 # Already deprecated but this was the only one it would let me install
          jnoortheen.nix-ide
          ms-azuretools.vscode-containers
          ms-vscode.cmake-tools
          rust-lang.rust-analyzer
          usernamehw.errorlens
          charliermarsh.ruff
          anthropic.claude-code
          ms-python.vscode-pylance
          vadimcn.vscode-lldb
          tamasfe.even-better-toml
          gruntfuggly.todo-tree
          mshr-h.veriloghdl
        ];
      };
      git = {
        enable = true;
        settings.user.name = "j-nac";
        settings.user.email = "jnac8080@gmail.com";
        lfs.enable = true;
      };
      ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "cornell-ece-linux" = {
            hostname = "ecelinux-16.ece.cornell.edu";
            user = "jn567";
          };
        };
      };
      plasma = {
        enable = true;
        workspace = {
          lookAndFeel = "org.kde.breezedark.desktop";
          colorScheme = "BreezeDark";
        };
        input.touchpads = [{
            name = "FOCA0001:00 2808:0106 Touchpad";
            vendorId = "2808";
            productId = "0106";
            naturalScroll = true;
            tapToClick = true;
        }];
        panels = [{
          location = "bottom";
          height = 44;
          lengthMode = "fit";
          hiding = "dodgewindows";

          widgets = [
            "org.kde.plasma.kickoff"
            "org.kde.plasma.icontasks"
            "org.kde.plasma.marginsseparator"
            "org.kde.plasma.systemtray"
            "org.kde.plasma.digitalclock"
          ];
        }];
      };
      fzf = {
        enable = true;
        enableZshIntegration = true;
      };
    };
    home.sessionPath = [ "$HOME/.cargo/bin" ];
    home.stateVersion = "25.11";
  };

  programs.zsh.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  programs.gamemode.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    libgcc

    zlib
    gfortran.cc.lib

    alsa-lib
    libjack2
    portaudio
    libsndfile

    openssl
    curl
    expat
  ];

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    libvirtd = {
      enable = true;
      qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
    };
  };

  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    kdePackages.plasma-browser-integration
    docker-compose
    dnsmasq
  ];
  nix.settings.auto-optimise-store = true;

  # Do NOT change stateVersion after initial install — it controls app data compatibility.
  system.stateVersion = "25.11";
}
