# Coverage

### Legend
⚠️ Feature regressed temporarily due to dependency or upstream (usually when zig updates this can happen)
 
⛔ Blocked due to upstream. Impossible to do until something gets fixed or added, usually listed in https://codeberg.org/GasInfinity/zitrus/issues/1

🟢 Fully implemented
🟡 Partially implemented
🔴 Implementation not started/missing critical things

🔋 High priority
🪫 Low priority

## Documentation

- 🟡 Mango
- 🟡 Horizon

## Tests

- 🟡 Horizon
- 🟡 Mango

## Formats (+ Tooling)
- 🟢 Smdh (tools/Smdh): Make / Dump
- 🟢 3dsx (tools/3dsx): Make / Dump
- 🟢 Pica (tools/Pica): Assemble / Disassemble
    - 🟢 Assemble: Only **Z**itrus**P**ica**Sh**ader's are implemented as an output format.
    - 🟢 Disassemble: Outputs **Z**itrus**P**ica**A**sse**m**bly. Either RAW instructions, ZPSH's or DVL's (.shbin) can be disassembled.
- 🟢 Firm (tools/Firm): Make / Info / Dump
- 🟡 Ncch (tools/Ncch): Make CXI / Dump / Info
    - 🟢 ExeFS (tools/ExeFs): Make / List / Dump
    - 🟢 RomFS (tools/RomFs): Make / List / Dump
- 🟡 Compression (tools/Compress):
    - 🟡 LZrev (Compress/LzRev): Decompression
    - 🟡 Yaz0 (Compress/Yaz): Decompression
    - 🟡 LZ10 (Compress/Lz10): Decompression
    - 🟡 LZ11 (Compress/Lz11): Decompression
- 🟡 Archives (tools/Archive):
    - 🟢 Darc (Archive/Darc): Make / List / Dump
    - 🟡 Sarc (Archive/Sarc): List / Dump
- 🟡 Layouts (tools/Layout):
    - 🟡 Image (Layout/Image): Dump
    - 🔴 Layout
    - 🔴 Animation 
- 🔴 Cro0 / Crr0
- 🔴 Cia

## Horizon

### Runtime
- 🟢 `threadlocal` variables & multithreading.
- 🟢 Panic / error reporting and tracing. 
    - *For the full stacktrace check `luma/errdisp.txt` in your SD card (with an emulator check you logs and/or enable application debug logging)*
    - 🟢 Segfaults (Data Aborts, Prefetch Aborts, ...).
    - 🔴 "Pretty" stacktraces with DWARF/Symbols
- 🟢 *Application* Test runner.
- 🟢 `std.Io`
    - 🟢 Synchronization through futexes
    - 🟡 POSIX'Y fd layer
        - 🟢 RomFS
        - 🟢 Sdmc
        - 🔴 Networking
    - 🔴 Concurrency
- 🔴⛔🔋 `libc`

### Services
    
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
- 🟡 `soc:U`
- 🟡 `ps:ps`
- 🟡 `pxi:ps9`
- 🟢 `Loader`
- 🔴 All other [services](https://www.3dbrew.org/wiki/Services_API) not listed here

### Library Applets

- 🟢 `error`
- 🟡 `swkbd`
- 🔴 All other [applets](https://www.3dbrew.org/wiki/NS_and_APT_Services#AppIDs) not listed here.

## Mango (PICA200 VK-like Graphics API)

### Backends
- 🟢 Horizon
- 🔴 Interface (for `freestanding` usage)

### Objects
- 🟢 Presentation engine: 240x400, 240x400x2, 240x800 + 240x320. `Double` or `Triple` buffered in `Mailbox` or `Fifo`.
- 🟡 Queues
    - 🟡 Fill (clear and fill operations)
    - 🟡 Transfer (copy and blit operations)
    - 🟢 Submit (`CommandBuffer` submission)
    - 🟢 Present (see `PresentationEngine`) 
- 🟢 `Semaphore`s
- 🟢 `DeviceMemory`
- 🟢 `Buffer`s
- 🟢 `Sampler`
- 🟢 `Image`s / ImageViews
- 🟢 `CommandPool`s
- 🟡 `Pipeline`s
    - 🟢 Lighting
    - 🔴 Shadows
    - 🔴 Geometry shaders
    - 🔴 Fog
    - 🔴 Gas
- 🟡 `CommandBuffer`s
    - 🔴 Shadow Rendering
    - 🔴 Gas Rendering
    - 🟡 Image Sampling
        - 🔴 Shadow textures
        - 🔴 Cubemaps

## Hardware

Whether register bits are present and/or relevant tooling (assemblers, disassemblers, etc...)

- 🟢 CSND
- 🟢 PXI
- 🟢 LGY
- 🟢 HID
- 🟢 I2C 
- 🟡 CPU (ARM9 & ARM11)
- 🟡 DSP
- 🟡 PICA200: Missing typing of some documented registers, mostly done.
