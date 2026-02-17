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

You should only have to run this once (because `/etc/nixos` is persisted).

## Gemini

Much of this comes from [a response by Gemini](gemini.md)
