# 🍊 zitrus

3DS homebrew library and toolchain written entirely in zig.

![bitmap example in a 2ds](https://github.com/GasInfinity/zitrus/blob/main/docs/images/bitmap-2ds.png?raw=true)

## Installation

```bash
# supporting zig 0.15.1
zig fetch --save git+https://github.com/GasInfinity/zitrus
```

Then add this to your `build.zig`:
```zig
const zitrus = @import("zitrus");

const zitrus_dep = b.dependency("zitrus", .{});
const zitrus_mod = zitrus_dep.module("zitrus");
// zitrus contains code useful for tooling outside of a 3DS environment.

// You must use the same target as `zitrus_mod`
const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/your_main.zig"),
    .target = zitrus.horizon_arm11, // this is currently deprecated as we will now have 'arm-3ds' in zig: https://github.com/ziglang/zig/pull/24938
    .optimize = optimize,
});

exe_mod.addImport("zitrus", zitrus_mod);

const exe = zitrus.addExecutable(b, .{
    .name = "homebrew.elf",
    .root_module = exe_mod,
});

// You can skip installing the elf but it is recommended to keep it for debugging purposes
b.installArtifact(exe);

const homebrew_smdh = zitrus.addMakeSmdh(b, .{
    .name = "homebrew.icn",
    .settings = b.path("path-to-smdh-settings.ziggy"), // look at any demo for a quick example or the schema in tools/make-smdh/settings.ziggy-schema
    .icon = b.path("path-to-icon.png/jpg/..."), // supported formats depends on zigimg image decoding. XXX: regressed until zigimg updates
});

// This step will convert your executable to 3dsx (the defacto homebrew executable format) to execute it in an emulator or real 3DS
const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "homebrew.3dsx", .exe = exe, .smdh = homebrew_smdh });
b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "homebrew.3dsx").step);
```

In your root file, you must also add this, as there's no way to implicitly tell zig to evaluate/import it automagically:
```
pub const panic = zitrus.panic;

comptime {
    _ = zitrus;
}
```

## Examples / Demos
Currently there are 5 examples in the `demo/` directory:
- [panic](demo/panic/) is a simple example that panics when opened to test panics and traces.
- [info](demo/info) is a simple app that currently shows the console region and model (will be updated to show more info over time).
- [bitmap](demo/bitmap/) is a port of the bitmap example in libctru's 3ds-examples.
- [flappy](demo/flappy) is a simple fully functional flappy bird clone written entirely with software blitting.
- [gpu](demo/gpu/) is a playground for [mango](src/mango.zig), a vulkan-like graphics API for the PICA200. All new features are tested there before getting pushed to the repo.

# Legend
⚠️ Feature regressed temporarily due to dependency or upstream (usually when zig updates this can happen)
 
⛔ Blocked due to upstream. Impossible to do until something gets fixed or added, usually listed in https://github.com/GasInfinity/zitrus/issues/1

🟢 Fully implemented
🟡 Partially implemented
🔴 Implementation not started/missing critical things

🔋 High priority
🪫 Low priority

# Tooling coverage
- 🟢⚠️ smdh creation (tools/smdh)
- 🟢 elf -> 3dsx conversion (tools/3dsx)
- 🟢 PICA200 shader assembler/disassembler:
    - 🟢 Instruction encoding/decoding
    - 🟢 Assembler/disassembler
    - 🟢 Diagnostics
    - 🟢 Output ZPSH files.
    - 🔴🪫 Output SHBIN/RAW files
- NCCH:
    - 🟢 ExeFS
    - 🔴 RomFS
    - 🔴 elf -> ExeFS .code
- 🔴 Everything not listed here
- 🟡🪫 Dumping, a.k.a: 3dsx/exefs --> bin/elf, smdh -> config + icons, etc...
    - 🟢⚠️ smdh -> config + icons
    - 🔴 Everything not listed here

# HOS Coverage
Zitrus is currently very work in progress, it's able to run basic homebrew but lots of things are missing (services, io, etc...)

- 🔴 Tests

## Runtime support
- 🟢 crt0/startup code
- 🟡⛔🔋 panic and error reporting and tracing
- 🔴⛔🔋 Io interface support (zig 0.16).
- 🔴🔋 Test runner.

## Gpu Support

- 🟢 Software rendering with Framebuffers
- 🟢 GX Commands
- 🟢 2D/3D Acceleration (a.k.a: REALLY using the Gpu to do things)
- 🟡🔋🔋 mango, a low-level, vulkan-like graphics api for the PICA200.

## Port/Service Support

- 🟢 `srv:`
- 🟢 `err:f`
- 🟡 `APT:S/A/U`
- 🟡 `hid:SPRV/USER`
- 🟡 `fs:USER`
- 🟡 `cfg:u/s/i`
- 🟢 `gsp::Gpu`
- 🟡🪫 `gsp::Lcd`
- 🔴 All other [services](https://www.3dbrew.org/wiki/Services_API) not listed here

# Mango coverage

- 🔴 Tests
- 🟡 Device HOS abstraction.
- 🟡 Memory / Buffers
- 🟡 Pipelines
- 🟡 CommandPool
- 🟡 CommandBuffer's
- 🟡 Images / ImageViews
- 🟡 Image Sampling
- 🔴⛔ Synchronization primitives / driver thread.
- 🔴⛔ Presentation engine.

- 🔴🪫 Device baremetal interface.

# Planned
- 🔴 C API

## Why?
I wanted to learn arm and always wanted to develop 3DS homebrew, also I searched and I haven't found any kind of zig package that doesn't use libctru, so I just started reading a lot and doing things. Furthermore, using only zig has a lot of advantages:
- Really simplified and easy development. You don't need complex toolchains, you just need the `zig` executable, that's it! (However, obviously it is recommended that you use devkitPRO's tools as I'm sure you'll need them. You want to use gdb, don't you?)
- Safety in `Debug` and `ReleaseSafe` modes. Zitrus currently uses the `ErrDisp` port to report panics and returned errors. The only missing thing is reporting return traces with debugging symbols (Currently only addresses are logged)
- Really useful and simple build-system (as you've seen the example `build.zig` is really small and makefiles are really arcane)

# Credits
- [3dbrew](https://www.3dbrew.org/wiki/Main_Page) is seriously the best resource if you need info about the 3DS hardware/software.
- [gbatek](https://problemkaputt.de/gbatek.htm#3dsreference) is the second best resource for low level info about the 3DS hardware.
- @devkitPro for the tooling, a starting point/reference for this project and reference for unknown/undocumented/unspecified things (e.g: libctru and how tf jumping to home menu worked).
- @azahar-emu/[azahar](https://github.com/azahar-emu/azahar) for providing an emulator to quickly test changes and the initial iterations.
- @LumaTeam/[Luma3DS](https://github.com/LumaTeam/Luma3DS/) for literally saving my life when trying to debug things in my 2DS.
