# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

let
  impermanence = builtins.fetchTarball {
    url = "https://github.com/nix-community/impermanence/archive/master.tar.gz";
  };
  home-manager = builtins.fetchTarball  {
    url = "https://github.com/nix-community/home-manager/archive/release-25.11.tar.gz";
  };
  nur-source = builtins.fetchTarball  {
    url = "https://github.com/nix-community/NUR/archive/main.tar.gz";
  };
  plasma-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/plasma-manager/archive/trunk.tar.gz";
  };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
      "${home-manager}/nixos"
    ];

  nixpkgs.overlays = [
    (final: prev: {
      nur = import nur-source { pkgs = prev; };
    })
  ];
  nixpkgs.config.allowUnfree = true;
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;


  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    "resume=/dev/nvme0n1p2"
  ];

  # Impermanence and roll back
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount /dev/nvme0n1p3 /btrfs_tmp

    # Only wipe if we are NOT resuming from hibernation
    if [[ ! -e /tmp/resume-at-boot ]]; then
        if [[ -e /btrfs_tmp/root ]]; then
            mkdir -p /btrfs_tmp/old_roots
            timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
            mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
        fi
        btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
    fi

    umount /btrfs_tmp
  '';

  # Critical persistence
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      "/etc/nixos"
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
        "VirtualBox VMs"
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
        ".config/signal"
      ];
      files = [
        ".screenrc"
        ".p10k.zsh"
      ];
    };
  };

  # Hibernation
  boot.resumeDevice = "/dev/nvme0n1p2";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "nixos"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  users.mutableUsers = false;
  users.users.j-nac = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
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
      signal-desktop
      ghidra-bin
      gh
      meslo-lgs-nf
      claude-code
      python314
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
        PROMPT='%n@%m %~ %# '
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
      };
      vscode = {
        enable = true;
        profiles.default.userSettings = {
          "editor.fontFamily" = "'MesloLGS NF', monospace";
          "workbench.iconTheme" = "material-icon-theme";
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
        ];
      };
      git = {
        enable = true;
        settings.user.name = "j-nac";
        settings.user.email = "jnac8080@gmail.com";
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
            "org.kde.plasma.kickoff"          # Application Launcher (Start Menu)
            "org.kde.plasma.icontasks"        # Icons-only Task Manager
            "org.kde.plasma.marginsseparator" # Spacer
            "org.kde.plasma.systemtray"       # System Tray (Clock, Wi-Fi, etc.)
            "org.kde.plasma.digitalclock"
          ];
        }];
      };
    };
    home.stateVersion = "25.11";
  };

  programs.firefox.enable = true;
  programs.zsh.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim
    wget
    kdePackages.plasma-browser-integration
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

}

