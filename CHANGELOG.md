# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]


## [2026-08-30 -> 2026-09-22]

- Added a lot more docs to `ChannelSound` based on discovered reverse engineered things.
- Added `ChannelSound.Engine` as an abstraction to manage state.
- Added initial `demo/mango/flappy`; simple flappy bird clone hw accelerated.
- Added `demo/sound/csnd`; playing sound via the CSND service directly.
- Added `blitImage` to `mango.CommandBuffer`
- Added `initAddress` to some service wrappers so you can bring your own shared address (if you don't want to use the global bump allocator)
- Added `horizon.fmt.ncch.romfs.Ivfc.write`
- Added support for adding a RomFS to NCCHs via `ncch make`
- Added lz compressors based/imported on/from zig's `std.compress.flate`
- Added `build/MakeCxi`, do note that `ncch make` it is still not finished but now supports compressed code.
- Added more hardware types in `zitrus.hardware`
- Added `pdn`, `mic:u`, `spi` and `i2c` services under `pdn.Sleep/Gpu/...`, `MicrophoneUser`, `Spi` and `I2c`
- Added the possibility to not switch stacks and use the kernel-provided stack by Horizon.
- Added `horizon.debug.simple_errdisp_panic` which doesn't collect any stacktrace and throws directly.
- Added `cdc` and `Gpio` services under `cdc.Hid/CSnd/Dsp/...`

- Added `horizon.ipc.Buffer.sendRequestWithResult` which doesn't map horizon results to zig errors.
- Added `horizon.services.Methods` for common methods applying to all services/ports. BREAKING: You may need to swap parameters to `.open`
- Added `horizon.ErrorDisplayManager.assertResult/Code`.
- Added `horizon.tls.initVariables` for rolling your own Thread wrappers (IMPORTANT! do this when spawning ANY thread not from `horizon.Thread.Impl` and not in -fsingle-threaded!)
- Added irq access capability reading/writing support to ncch making.
- `ServiceManager.command.GetServiceHandle` -> `ServiceManager.command.GetService`
- BREAKING: General ipc improvements, structs are now not mandatory to be toplevel in req/resp; i.e you can now just expect a `bool` return value instead of wrapping it in a struct.
  This is only BREAKING to those who use services in a low-level way; sorry!
- BREAKING: Now you can set the type in `ipc.Mapped(T, permissions)` and `ipc.Static(T, index)`
- Added `horizon.ipc.Embedded` and `horizon.ipc.EmbeddedSentinel` for embedded slices in the IPC buffer.

- Changed `horizon.fmt.ncch.ExtendedHeader` to `horizon.fmt.ncch.Header.Extended`
- Changed `demo/mango/texture_loading` to load the texture from the RomFS instead of embedding it.
- Moved `zitrus.horizon.fmt.ncch.ExtendedHeader` -> `zitrus.horizon.fmt.ncch.Header.Extended`
- Begin moving `zitrus.horizon.services.X` to it's service acronyms, deprecating the aliases. For example `services.SocketUser` is now `services.soc.User`;
  services that only have one service or provide multiple ones with the same requests will still be in its acronym form in `services`, e.g `services.Ptm`.

- Removed `zitrus.horizon.fmt.smdh` (-> `zitrus.horizon.fmt.ncch.smdh`), it was deprecated a LONG time ago.
- Removed `zitrus.horizon.ipc.Codec.write` (-> `bufWrite`), it's just better.

## [2026-08-21] BREAKING

- Added more validation.
- Added `allocatePrivate`, `freePrivate`, `hostAllocator`, `hostToDevice`, `flushCachedMemoryRanges` and `invalidateCachedMemoryRanges` to `mango.Device` as a new
memory management flow (CPU-mapped pointers & `mango.DeviceSlice`)
- Added `mango.Display` with `configureDisplay`, `resetDisplay` and `getDisplayImages` to `mango.Device`
- Added support for fog; with `createFogLookupTable`, `recreateFogLookupTable`, `destroyFogLookupTable` in `mango.Device` and `setTextureCombinersEffect`, `setTextureCombinersEffectDepthFlip`, `setFogColor`, `bindFogTable` in `mango.CommandBuffer`.
- Added memory barriers; `memoryBarrier`. You can invalidate either currently bound render attachments (color or depth buffer) or sampled images.
- Added support for filling memory in command buffers; `clearColorImage` and `clearDepthStencilImage` can now be called in `mango.CommandBuffer`s.
  Note that it's less efficient than clearing before a command buffer (e.g with `clearColorImage` in `mango.Device`) due to more CPU->GPU->CPU roundtrips.
  Be careful! Updating memory which may be cached by the GPU may need a memory barrier!

- Changed how resources are allocated. They now don't accept a separate allocator in preparation for preheating and possible pooling.
  With the possibility of disabling dynamic object allocation (i.e only static preallocations and `OutOfMemory` when out of them)
- Changed `bindIndexBuffer`, `bindVertexBuffers` in `mango.CommandBuffer` so they accept `mango.DeviceSlice`
- Changed methods that accepted `mango.Buffer` to `mango.DeviceSlice`
- Changed how texture combiners are handled, it is now only mandatory to configure the *last* texture combiner, which is the one affecting the final output.
  Now it's possible to partially update buffer sources and texture combiners; `setTextureCombiners`, `setTextureCombinerBufferSources`, `setTextureCombinersBufferColor`
- Changed how NDC -> depth is handled; parameters are now explicit. `setViewport` now only accepts the viewport rect, `setDepthBias` has been removed in favor of just adding the value yourself in `setDepthParameters`, which control the parameters from going from NDC ([-1, 0]) to depth ([0, 1]).

- Removed `createSwapchain`, `destroySwapchain`, `getSwapchainImages` from `mango.Device`. Use the new `mango.Display` APIs
- Removed `allocateMemory`, `freeMemory`, `mapMemory`, `unmapMemory`, `flushMappedMemoryRanges` and `invalidateMappedMemoryRanges` in favor of the new ones.
- Removed `setFrontFace` from `mango.CommandBuffer`; just use `setCullMode`
- Removed `mango.Surface` and `mango.Swapchain`
- Removed `device.getQueue` in favour of methods in `mango.Device`
- Removed mango tests, I'll have to find another way to test things.
- Removed the `gpu` demo (which was a mess as it was iterated quickly and was mainly used to test things); 
  next new demos will be done in the `mango` subdirectory.

- Fixed an oops in `mango.CommandBuffer` that caused integer overflows on highly used big streams.
- Fixed some memory allocation bugs by dropping `zalloc`.
- Fixed some bitrotted services

- Dropped `zalloc` from dependency tree

### [2026-07-08]

- Workaround GSP event timeout caused by going to the rosalina menu, causing the driver to panic (the IRQ timing out is basically losing the GPU)
