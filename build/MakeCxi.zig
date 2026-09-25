//! A wrapper to simplify making a CXI with the build system.

pub const Options = struct {
    name: ?[]const u8 = null,
    exe: *Build.Step.Compile,

    settings: Build.LazyPath,
    smdh: ?Build.LazyPath = null,
    romfs: ?Build.LazyPath = null,
    /// Overrides the unique and variation part of the title id
    title_id: ?u32 = null,
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

/// The underlying `Build.Step.Run` which makes the NCCH.
run: *Build.Step.Run,

/// The generated NCCH file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) MakeCxi {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) MakeCxi {
    const name = options.name orelse b.fmt("{s}.cxi", .{std.fs.path.stem(options.exe.name)});

    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("make cxi({s})", .{name}));
    make.addArgs(&.{ "ncch", "make" });

    make.addArg("--elf");
    make.addArtifactArg(options.exe);

    make.addArg("--settings");
    make.addFileArg(options.settings);

    if (options.smdh) |smdh| {
        make.addArg("--icon");
        make.addFileArg(smdh);
    }

    if (options.romfs) |romfs| {
        make.addArg("--romfs");
        make.addFileArg(romfs);
    }

    if (options.title_id) |title_id| {
        make.addArgs(&.{"--title-id", b.fmt("0x{X:0>8}", .{title_id})});
    }

    make.addArg("--output");
    const out = make.addOutputFileArg(name);

    return .{
        .name = name,
        .run = make,
        .out = out,
    };
}

pub fn install(make: MakeCxi, b: *Build, options: InstallOptions) void {
    const dest_sub_path = options.dest_sub_path orelse make.name;
    const install_cxi = b.addInstallFileWithDir(make.out, options.install_dir, dest_sub_path);

    b.getInstallStep().dependOn(&install_cxi.step);
}

const MakeCxi = @This();

const std = @import("std");
const Build = std.Build;
