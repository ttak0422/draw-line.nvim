{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = [
    pkgs.neovim
    pkgs.stylua
    pkgs.luaPackages.luacheck
  ];
}
