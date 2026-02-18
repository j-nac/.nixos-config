# README

This is my NixOS setup. There are some nice things.

- Impermanence with btrfs
- Hibernation for a laptop computer
- Home manager

## Password Management

Generate a hash and save to a file in the directory `/persist/etc/nixos-passwords`

## Symlinking

Make sure to symlink the config in `~/.nixos-config` to `/etc/nixos` with the following command:

`sudo ln -s ~/.nixos-config/* /etc/nixos`

You need to do this the first time and if you ever add or remove files (because `/etc/nixos` is persisted).

For re-symlinking, `rm -rf /etc/nixos` and then do the symlink command.

## Gemini

Much of this comes from [a response by Gemini](gemini.md)
