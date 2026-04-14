![Zitrus Logo](https://codeberg.org/GasInfinity/zitrus/raw/branch/main/assets/zitrus-logo.png)

---
![Zig support](https://img.shields.io/badge/Zig-0.16.x-color?logo=zig&color=%23f3ab20)
  
3DS homebrew sdk written entirely in zig.

## Installation

> [!NOTE]
> Not even the language this project is written in is 1.0
>
> You acknowledge that any amount of breaking changes may occur until 
> the first stable (minor) release, a.k.a `0.1.0`. No ETA is given.

```bash
zig fetch --save git+https://codeberg.org/GasInfinity/zitrus
```

Then add this to your `build.zig`:
```zig
const zitrus = @import("zitrus");

const zitrus_dep = b.dependency("zitrus", .{});

// zitrus contains code useful for tooling outside of a 3DS environment.
const zitrus_mod = zitrus_dep.module("zitrus");

const exe = b.addExecutable(.{
    .name = "app.elf",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .arm,
            .os_tag = .@"3ds",
        }),
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zitrus", .module = zitrus_mod },
        },
        .zig_lib_dir = zitrus_dep.namedLazyPath("juice/zig_lib"),
    }),
});

// 3DSX's are PIE's
exe.pie = true;

// Needed for any binary which targets the 3DS
exe.setLinkerScript(zitrus_dep.namedLazyPath("horizon/ld"));

// You can skip installing the elf but it is recommended to keep it for debugging purposes
b.installArtifact(exe);

const smdh: zitrus.MakeSmdh = .init(zitrus_dep, .{
    .settings = b.path("path-to-smdh-settings.zon"), // look at any demo for a quick sample.
    .icon = b.path("path-to-icon.png/jpg/..."), // supported formats depends on zigimg image decoding.
});

// See `MakeRomFs` if you need something patchable unlike `@embedFile`.

// This step will convert your executable to 3dsx (the defacto homebrew executable format) to execute it in an emulator or real 3DS
const final_3dsx: zitrus.Make3dsx = .init(zitrus_dep, .{ .exe = exe, .smdh = smdh });
final_3dsx.install(b, .default);
```

In your root file, you must also add this, as there's no way to implicitly tell zig to evaluate/import/use it automagically:
```zig
pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;
```

## Examples / Demos
Currently there are multiple examples in the `demo/` directory. To build them, you must have `zig 0.16.0` in your path and run `zig build`.
- [mango](demo/mango/) contains samples of how to use the mango graphics api.
- [io](demo/io) contains samples of how `std.Io` may be used.

- [panic](demo/panic/) is a simple example that panics when opened to test panics and traces.
- [info](demo/info) is a simple app that currently shows the console region and model (will be updated to show more info over time).
- [bitmap](demo/bitmap/) is a port of the bitmap example in libctru's 3ds-examples.
- [flappy](demo/flappy) is a simple fully functional flappy bird clone written entirely with software blitting.
- [gpu](demo/gpu/) is a playground for [mango](src/mango.zig), bleeding edge features are tested there. Not really an example per-se.

--- 

You can (and are encouraged) to look at the `tools` directory as it is a good example of how to use the API's `zitrus` provides outside (and inside!) of a 3DS environment. Almost all tools are self-contained and span 50-300 LOC.

## Coverage

Moved to [Coverage.md](docs/Coverage.md)

## Contributing

**Please refrain from using LLMs to make PRs and/or Issues as-is**

Currently there's no place to discuss contributions or usage of the SDK, feel free to open an issue if you want to use `zitrus` but don't know how to start (remember, lack of documentation is *also* an issue!)

## Why

Moved to [Why.md](docs/Why.md)

# Credits
- [3dbrew](https://www.3dbrew.org/wiki/Main_Page) is seriously the best resource if you need info about the 3DS hardware/software.
- [gbatek](https://problemkaputt.de/gbatek.htm#3dsreference) is the second best resource for low level info about the 3DS hardware.
- @devkitPro for the tooling, a starting point/reference for this project and reference for unknown/undocumented/unspecified things (e.g: libctru and how tf jumping to home menu worked).
- @azahar-emu/[azahar](https://github.com/azahar-emu/azahar) for providing an emulator to quickly test changes and the initial iterations.
- @LumaTeam/[Luma3DS](https://github.com/LumaTeam/Luma3DS/) for literally saving my life when trying to debug things in my 2DS.
- [@TuxSH](https://github.com/TuxSH/) for his kernel decompilations which allowed (and allow) me to understand more how it works.
