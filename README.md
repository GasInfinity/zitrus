![Zitrus Logo](https://github.com/GasInfinity/zitrus/blob/main/assets/zitrus-logo.png?raw=true)

---
![Zig support](https://img.shields.io/badge/Zig-0.15.x-color?logo=zig&color=%23f3ab20)
  
3DS homebrew sdk written entirely in zig.

## Installation

> [!NOTE]
> Not even the language this project is written in is 1.0
>
> You acknowledge that any amount of breaking changes may occur until 
> the first stable (minor) release, a.k.a `0.1.0`. No ETA is given.

```bash
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
    .icon = b.path("path-to-icon.png/jpg/..."), // supported formats depends on zigimg image decoding.
});

// See `addMakeRomFs` if you need something patchable unlike `@embedFile`.

// This step will convert your executable to 3dsx (the defacto homebrew executable format) to execute it in an emulator or real 3DS
const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "homebrew.3dsx", .exe = exe, .smdh = homebrew_smdh });
b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "homebrew.3dsx").step);
```

In your root file, you must also add this, as there's no way to implicitly tell zig to evaluate/import it automagically:
```zig
pub const panic = zitrus.horizon.panic;

comptime {
    _ = zitrus;
}
```

## Examples / Demos
Currently there are multiple examples in the `demo/` directory. To build them, you must have `zig 0.15.1` in your path and run `zig build`.
- [mango](demo/mango/) contains samples of how to use the mango graphics api.

- [panic](demo/panic/) is a simple example that panics when opened to test panics and traces.
- [info](demo/info) is a simple app that currently shows the console region and model (will be updated to show more info over time).
- [bitmap](demo/bitmap/) is a port of the bitmap example in libctru's 3ds-examples.
- [flappy](demo/flappy) is a simple fully functional flappy bird clone written entirely with software blitting.
- [gpu](demo/gpu/) is a playground for [mango](src/mango.zig), bleeding edge features are tested there. Not really an example per-se.


# Legend
⚠️ Feature regressed temporarily due to dependency or upstream (usually when zig updates this can happen)
 
⛔ Blocked due to upstream. Impossible to do until something gets fixed or added, usually listed in https://github.com/GasInfinity/zitrus/issues/1

🟢 Fully implemented
🟡 Partially implemented
🔴 Implementation not started/missing critical things

🔋 High priority
🪫 Low priority

# Tooling coverage
- 🟢 Smdh creation (tools/Smdh)
- 🟢 Elf -> 3dsx conversion (tools/3dsx)
- 🟢 PICA200 shader assembler/disassembler (tools/Pica):
    - 🟢 Instruction encoding/decoding
    - 🟢 Assembler
    - 🔴🪫 Disassembler
    - 🟢 Diagnostics
    - 🟢 Output ZPSH files.
    - 🔴🪫 Output SHBIN/RAW files
- 🟡 NCCH (tools/Ncch):
    - 🟢 ExeFS (tools/ExeFs)
    - 🟢 RomFS (tools/RomFs)
    - 🔴 elf -> ExeFS .code
- 🔴 Everything not listed here
  
- 🟡🪫 Dumping, a.k.a: 3dsx/exefs --> bin/elf, smdh -> config + icons, etc...
    - 🟢 Smdh -> config + icons
    - 🟡 NCCH:
        - 🟢 LZrev decompressor.
        - 🟢 ExeFS
        - 🔴 RomFS
    - 🔴 Everything not listed here

# HOS Coverage
Zitrus is currently very work in progress, it's able to run basic homebrew but lots of things are missing (services, io, etc...)

- 🟡 Tests
- 🟡 C API
- 🟡 Docs

## Runtime support
- 🟢 crt0/startup code
- 🔴⛔ Thread local variables.
- 🟡⛔🔋 panic and error reporting and tracing.
- 🔴⛔🔋 Io interface support (zig 0.16).
- 🟡⛔🔋 *Application* Test runner.

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
- 🟢 `ir:rst`
- 🟡 `fs:USER/LDR`
- 🟡 `cfg:u/s/i`
- 🟢 `gsp::Gpu`
- 🟡🪫 `gsp::Lcd`
- 🟡 `ns:s`
- 🟢 `ns:p/c`
- 🟡 `csnd:SND`
- 🟡🪫 `pm:app`
- 🟢 `pm:dbg`
- 🔴 All other [services](https://www.3dbrew.org/wiki/Services_API) not listed here

## Applet Support
- 🟢 `error`
- 🟡 `swkbd`
- 🔴 All other [applets](https://www.3dbrew.org/wiki/NS_and_APT_Services#AppIDs) not listed here.

# Mango coverage

- 🔴 Tests
- 🟡 C API
- 🟡 Docs

- 🟡 Device HOS implementation.
- 🟡 Queues
    - 🟡 Fill (clear and fill operations)
    - 🟡 Transfer (copy and blit operations)
    - 🟢 Submit (`CommandBuffer` submission)
    - 🟡 Present (see `PresentationEngine` support)
- 🟡 Memory / Buffers
- 🟡 Pipelines
- 🟡 CommandPool
    - 🟢 `CommandBuffer` recycling
    - 🔴 Native buffer pooling/reusing
    - 🔴 Prewarm parameters.
- 🟡 CommandBuffer's
- 🟡 Images / ImageViews
    - 🟡 Up to 8 `Image` layers
    - 🟡 Up to 8 mipmap levels (1024x1024 -> 8x8)
- 🟡 Image Sampling
- 🟢 Synchronization primitives / driver thread.
- 🟡 Presentation engine.
    - 🟢 2D (Top and bottom)
    - 🟢 3D (Top, 2 layers per image)
    - 🟡 Full resolution (Top 240x800 swapchain, needs testing but should work)

- 🔴🪫 Device `HAL` abstraction.
- 🔴🪫 Device baremetal implementation (prerequsite: `HAL` abstraction).

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
