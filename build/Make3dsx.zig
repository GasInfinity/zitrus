//! A wrapper to simplify making a 3DSX with the build system.

pub const Options = struct {
    name: ?[]const u8 = null,
    exe: *Build.Step.Compile,
    smdh: ?Build.LazyPath = null,
    romfs: ?Build.LazyPath = null,
};

pub const Config = struct {
    tools_artifact: *Build.Step.Compile,
};

pub const InstallOptions = struct {
    pub const default: InstallOptions = .{ .install_dir = .bin, .dest_sub_path = null };

    /// Which installation directory to put the main output file into.
    install_dir: Build.InstallDir = .bin,

    /// If non-null, adds additional path components relative to bin dir, and
    /// overrides the basename of the Compile step for installation purposes.
    dest_sub_path: ?[]const u8 = null,
};

name: []const u8,

/// The underlying `Build.Step.Run` which makes the 3DSX.
run: *Build.Step.Run,

/// The generated 3DSX file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) Make3dsx {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) Make3dsx {
    const name = options.name orelse b.fmt("{s}.3dsx", .{std.fs.path.stem(options.exe.name)});

    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("make 3dsx ({s})", .{name}));
    make.addArgs(&.{ "3dsx", "make" });
    make.addArtifactArg(options.exe);

    if (options.smdh) |smdh| {
        make.addArg("--smdh");
        make.addFileArg(smdh);
    }

    if (options.romfs) |romfs| {
        make.addArg("--romfs");
        make.addFileArg(romfs);
    }

    const out = make.addOutputFileArg(name);

    return .{
        .name = name,
        .run = make,
        .out = out,
    };
}

pub fn install(make: Make3dsx, b: *Build, options: InstallOptions) void {
    const dest_sub_path = options.dest_sub_path orelse make.name;
    const install_3dsx = b.addInstallFileWithDir(make.out, options.install_dir, dest_sub_path);

    b.getInstallStep().dependOn(&install_3dsx.step);
}

const Make3dsx = @This();

const std = @import("std");
const Build = std.Build;
