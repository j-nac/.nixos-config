# README

This is my NixOS setup. There are some nice things.

- Impermanence with btrfs
- Hibernation for a laptop computer
- Home manager

## Password Management

Generate a hash and save to a file in a secrets directory.

## Symlinking

Make sure to symlink the config in `~/.nixos-config` to `/etc/nixos` with the following command:

`sudo ln -s ~/.nixos-config/* /etc/nixos/`

## Gemini

Much of this comes from [a response by Gemini](gemini.md)
