const named_parsers = .{ .@"in.elf" = clap.parsers.string, .@"out.3dsx" = clap.parsers.string, .romfs = clap.parsers.string, .smdh = clap.parsers.string };
const cli_params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\-r, --romfs <romfs>    RomFS file (a.k.a: read-only filesystem that contains extra data) to embed
    \\-s, --smdh <smdh>      SMDH file (a.k.a: icon, region and extra config) to embed
    \\<in.elf>               The elf file to process
    \\<out.3dsx>             The output 3dsx file to write
    \\
);

fn showHelp(stderr: anytype) !void {
    try std.fmt.format(stderr,
        \\ zitrus - make-3dsx
        \\ converts a supported elf file to 3dsx
        \\
        \\
    , .{});
    try clap.help(stderr, clap.Help, &cli_params, .{});
}

pub fn main(arena: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const stderr = std.io.getStdErr().writer();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &cli_params, named_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = arena,
    }) catch |err| {
        try showHelp(stderr);
        diag.report(stderr, err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null or res.positionals[1] == null) {
        try showHelp(stderr);
        return;
    }

    // TODO: Handle RomFS and SMDH
    if (res.args.romfs != null) {
        @panic("TODO");
    }

    const in = res.positionals[0] orelse unreachable;
    const out = res.positionals[1] orelse unreachable;

    const cwd = std.fs.cwd();
    const input_file = cwd.openFile(in, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Input file '{s}' not found\n", .{in});
            return;
        },
        else => {
            std.debug.print("Could not open input file '{s}': {s}", .{ in, @errorName(err) });
            return err;
        },
    };

    defer input_file.close();

    const output_file = cwd.createFile(out, .{}) catch |err| {
        std.debug.print("Could not create/open output file '{s}' for writing: {s}", .{ out, @errorName(err) });
        return err;
    };
    defer output_file.close();

    var output_buffered = std.io.bufferedWriter(output_file.writer());

    const smdh_data = if (res.args.smdh) |smdh_path| data: {
        const smdh_file = cwd.openFile(smdh_path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Smdh file '{s}' not found\n", .{smdh_path});
                return;
            },
            else => {
                std.debug.print("Could not open smdh file '{s}': {s}", .{ smdh_path, @errorName(err) });
                return err;
            },
        };
        var smdh_data: smdh.Smdh = undefined;

        const read = try smdh_file.readAll(std.mem.asBytes(&smdh_data));

        if (read < @sizeOf(smdh.Smdh) or !std.mem.eql(u8, &smdh_data.magic, smdh.magic)) {
            std.debug.print("Smdh file '{s}' is invalid/corrupted", .{smdh_path});
            return;
        }

        break :data smdh_data;
    } else null;
    zitrus_tooling.@"3dsx".make(input_file.reader(), output_buffered.writer(), .{
        .allocator = arena,
        .smdh = smdh_data,
    }) catch |err| switch (err) {
        error.InvalidMachine => {
            std.debug.print("Error processing elf: The elf machine is not ARM\n", .{});
            return err;
        },
        error.NotExecutable => {
            std.debug.print("Error processing elf: The elf is not executable\n", .{});
            return err;
        },
        error.InvalidEntryAddress => {
            std.debug.print("Error processing elf: The entry address is not the base address of the .text segment\n", .{});
            return err;
        },
        error.UnalignedSegmentMemory => {
            std.debug.print("Error processing elf: Segment memory is not aligned to ARM word alignment (4 bytes)\n", .{});
            return err;
        },
        error.UnalignedSegmentFileMemory => {
            std.debug.print("Error processing elf: Segment file memory is not aligned to ARM word alignment (4 bytes)\n", .{});
            return err;
        },
        error.NonContiguousSegment => {
            std.debug.print("Error processing elf: Non-continuous segments\n", .{});
            return err;
        },
        error.CodeSegmentMustBeFirst => {
            std.debug.print("Error processing elf: The .text/.code segment must be the first to appear\n", .{});
            return err;
        },
        error.RodataSegmentMustBeSecond => {
            std.debug.print("Error processing elf: The .rodata segment must be the second to appear or not appear at all\n", .{});
            return err;
        },
        error.DataSegmentMustBeLast => {
            std.debug.print("Error processing elf: The .data segment must be the last segment to appear\n", .{});
            return err;
        },
        error.NonDataSegmentHasBss => {
            std.debug.print("Error processing elf: Non .data segment has bss\n", .{});
            return err;
        },
        error.InvalidSegment => {
            std.debug.print("Error processing elf: More usable segments than expected\n", .{});
            return err;
        },
        else => {
            std.debug.print("Could not process elf: {s}\n", .{@errorName(err)});
            return err;
        },
    };

    try output_buffered.flush();
}

const std = @import("std");
const clap = @import("clap");
const zitrus_tooling = @import("zitrus-tooling");
const smdh = zitrus_tooling.smdh;
