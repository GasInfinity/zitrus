//! A wrapper to simplify making a FIRM with the build system.

pub const Options = struct {
    pub const CopyMethod = enum { ndma, xdma, memcpy };
    pub const Section = union(enum) {
        pub const Binary = struct {
            path: Build.LazyPath,
            address: u32,
            method: CopyMethod,
        };

        pub const Executable = struct {
            exe: *Build.Step.Compile,
            method: CopyMethod,
        };

        none,
        binary: Binary,
        executable: Executable,

        pub fn bin(path: Build.LazyPath, address: u32, method: CopyMethod) Section {
            return .{ .binary = .{ .path = path, .address = address, .method = method } };
        }

        pub fn exe(artifact: *Build.Step.Compile, method: CopyMethod) Section {
            return .{ .executable = .{ .exe = artifact, .method = method } };
        }
    };

    name: []const u8,
    arm9: Section.Executable,
    arm11: Section.Executable,
    boot_priority: u32 = 0,
    extra: [2]Section = .{ .none, .none },
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

/// The underlying `Build.Step.Run` which makes the FIRM.
run: *Build.Step.Run,

/// The generated FIRM file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) MakeFirm {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) MakeFirm {
    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("make firm ({s})", .{options.name}));
    make.addArgs(&.{ "firm", "make" });

    const Cpu = enum { arm9, arm11 };
    const entries: []const Options.Section.Executable = &.{ options.arm9, options.arm11 };

    for (entries, std.enums.values(Cpu)) |entry, cpu| {
        make.addArg("--elf");
        make.addArtifactArg(entry.exe);
        make.addArg(@tagName(cpu));
        make.addArg(@tagName(entry.method));
    }

    for (&options.extra) |extra| switch (extra) {
        .none => {},
        .binary => |bin| {
            make.addArg("--section");
            make.addFileArg(bin.path);
            make.addArg(b.fmt("0x{X:0>8}", .{bin.address}));
            make.addArg(@tagName(bin.method));
        },
        .executable => |exe| {
            make.addArg("--elf");
            make.addArtifactArg(exe.exe);
            make.addArg("raw");
            make.addArg(@tagName(exe.method));
        },
    };

    make.addArg("--output");
    const out = make.addOutputFileArg(options.name);

    return .{
        .name = options.name,
        .run = make,
        .out = out,
    };
}

pub fn install(make: MakeFirm, b: *Build, options: InstallOptions) void {
    const dest_sub_path = options.dest_sub_path orelse make.name;
    const install_firm = b.addInstallFileWithDir(make.out, options.install_dir, dest_sub_path);

    b.getInstallStep().dependOn(&install_firm.step);
}

const MakeFirm = @This();

const std = @import("std");
const Build = std.Build;
