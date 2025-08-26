{
  description = "A Nix-flake-based Zig development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig.url = "github:silversquirl/zig-flake/compat";
    zls.url = "github:zigtools/zls";

    zig.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.zig-overlay.follows = "zig";
  };

  outputs = { nixpkgs, zig, zls, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
        zpkgs = zig.packages."${system}";
        zlspkgs = zls.packages."${system}";
      });
    in
    {
      devShells = forEachSupportedSystem ({ pkgs, zpkgs, zlspkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            zpkgs.zig_0_15_1
            zlspkgs.zls 
            lldb
          ];
        };
      });
    };
}
