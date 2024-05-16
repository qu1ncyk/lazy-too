{lib, ...}: {
  imports = [
    ./plugin-dir.nix
    ./interface.nix
    ./wrap-neovim.nix
  ];

  name = lib.mkDefault "lazy-too";
  version = lib.mkDefault "0";
}
