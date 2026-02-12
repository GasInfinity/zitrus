# Why?

I wanted to learn arm and always wanted to develop 3DS homebrew, also I searched and I haven't found any kind of zig package that doesn't use libctru, so I just started reading a lot and doing things. Furthermore, using only zig has a lot of advantages:
- Really simplified and easy development. You don't need complex toolchains, you just need the `zig` executable, that's it. The tools `zitrus` provides also have no dependencies, they'll work on any platform that zig supports! You can still use devkitPRO's binutils if you need.
- Safety in `Debug` and `ReleaseSafe` modes. Zitrus currently uses the `ErrDisp` port to report panics and returned errors. The only missing thing is reporting return traces with debugging symbols (Currently only addresses are logged)
- Really useful and simple build-system (as you've seen the example `build.zig` is really small and makefiles are really arcane)
