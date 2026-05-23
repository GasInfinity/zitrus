//! A wrapper to simplify making PTX files with the build system.

pub const Options = struct {
    pub const Format = enum {
        abgr8888,
        bgr888,
        rgba5551,
        rgb565,
        rgba4444,
        ia88,
        hilo88,
        i8,
        a8,
        ia44,
        i4,
        a4,
        etc1,
        etc1a4,
    };

    pub const Quality = enum { low, medium, high };

    name: []const u8,
    file: std.Build.LazyPath,
    /// Conversion is lossy if needed.
    format: Format = .abgr8888,
    quality: Quality = .medium,
};

pub const Config = struct {
    tools_artifact: *Build.Step.Compile,
};

name: []const u8,

/// The underlying `Build.Step.Run` which actually makes the PTX.
run: *Build.Step.Run,

/// The generated file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) MakePtx {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) MakePtx {
    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("make ptx ({s})", .{options.name}));
    make.addArgs(&.{ "pica", "texture", "make" });
    make.addFileArg(options.file);

    make.addArg("-o");
    const out = make.addOutputFileArg(options.name);

    make.addArgs(&.{"-f", @tagName(options.format), "-q", @tagName(options.quality) });
    return .{
        .name = options.name,
        .run = make,
        .out = out,
    };
}

const MakePtx = @This();

const std = @import("std");
const Build = std.Build;
