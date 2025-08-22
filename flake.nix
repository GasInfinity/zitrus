{
  description = "A Nix-flake-based Zig development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zigpkgs.url = "github:silversquirl/zig-flake";
  };

  outputs = { nixpkgs, zigpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
        zpkgs = zigpkgs.packages."${system}";
      });
    in
    {
      devShells = forEachSupportedSystem ({ pkgs, zpkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [ zpkgs.zig_0_15_1 lldb ];
        };
      });
    };
}
