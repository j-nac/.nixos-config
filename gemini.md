# Gemini

Setting up NixOS with **Btrfs Impermanence** and **Hibernation** is a "power user" move that ensures your system stays clean while remaining functional.

Since your `/` (root) will be wiped every boot, the biggest risk is getting **locked out** because your user password or SSH keys vanished. We will address that by persisting the necessary files.

### 1. Partitioning & Subvolumes

Boot from the NixOS ISO and open a terminal. We'll use a single drive (e.g., `/dev/nvme0n1`).

```bash
# 1. Create partitions (1GB Boot, 32GB Swap for hibernation, rest for Data)
# Note: Swap must be >= RAM size for reliable hibernation.
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 1024MB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart swap linux-swap 1024MB 33GB
parted /dev/nvme0n1 -- mkpart primary btrfs 33GB 100%

# 2. Format
mkfs.vfat -F 32 -n boot /dev/nvme0n1p1
mkswap -L swap /dev/nvme0n1p2
mkfs.btrfs -L nixos /dev/nvme0n1p3

# 3. Create Btrfs Subvolumes
mount /dev/nvme0n1p3 /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/nix
btrfs subvolume create /mnt/persist
btrfs subvolume create /mnt/log
# Create a blank snapshot of root to "roll back" to every boot
btrfs subvolume snapshot -r /mnt/root /mnt/root-blank
umount /mnt

```

---

### 2. Mounting for Installation

Mount the subvolumes in the correct hierarchy:

```bash
mount -o subvol=root,compress=zstd,noatime /dev/nvme0n1p3 /mnt

# Create mount points
mkdir -p /mnt/{boot,nix,persist,var/log,swap}
mount /dev/nvme0n1p1 /mnt/boot
mount -o subvol=nix,compress=zstd,noatime /dev/nvme0n1p3 /mnt/nix
mount -o subvol=persist,compress=zstd,noatime /dev/nvme0n1p3 /mnt/persist
mount -o subvol=log,compress=zstd,noatime /dev/nvme0n1p3 /mnt/var/log

swapon /dev/nvme0n1p2

```

---

### 3. Configuration (`configuration.nix`)

Generate the config with `nixos-generate-config --root /mnt`, then edit `/mnt/etc/nixos/configuration.nix`.

#### **How to Prevent Lockout**

To ensure you can log in after the root is wiped, you must persist your user password and machine ID.

```nix
{ config, pkgs, lib, ... }: {
  imports = [ ./hardware-configuration.nix ];

  # 1. Impermanence: Roll back root on boot
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount /dev/nvme0n1p3 /btrfs_tmp
    if [[ -e /btrfs_tmp/root ]]; then
        mkdir -p /btrfs_tmp/old_roots
        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
    fi
    btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
    umount /btrfs_tmp
  '';

  # 2. Critical Persistence (Prevents Lockout)
  # You need the 'impermanence' module from GitHub or manually bind mount
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"
      "/var/lib/nixos"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
      # To keep passwords, you can persist /etc/shadow or use hashedPassword
    ];
  };

  # 3. User & Password (The "No Lockout" way)
  users.mutableUsers = false; # Forces passwords to be defined in Nix
  users.users.yourname = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # Generate this with: mkpasswd -m sha-512
    hashedPassword = "$6$long_random_hash_here..."; 
  };

  # 4. Hibernation
  boot.resumeDevice = "/dev/nvme0n1p2"; # Your swap partition
  
  # 5. Standard Setup
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true; # Example: KDE Plasma 6
}

```

---

### 4. Final Steps

1. Run `nixos-install`.
2. Set a root password if prompted (though `mutableUsers = false` and `hashedPassword` is safer).
3. Reboot.

**Crucial Note on Hibernation:** If you use a Btrfs swap **file** instead of a partition, you must calculate the `resume_offset`. Using a dedicated swap **partition** (as shown above) is much simpler for your first setup.

Would you like me to show you how to set up the **Impermanence Flake** to automate the folder linking?

[NixOS Btrfs Guide](https://www.youtube.com/watch?v=2QjzI5dXwDY)
This video provides a modern walkthrough of partitioning and NixOS installation which can be adapted for Btrfs workflows.