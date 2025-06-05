const named_parsers = .{
    .in = clap.parsers.string,
    .out = clap.parsers.string,
    .romfs = clap.parsers.string,
    .smdh = clap.parsers.string,
};
const cli_params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\-r, --romfs <romfs>    RomFS file (a.k.a: read-only filesystem that contains extra data) to embed
    \\-s, --smdh <smdh>      SMDH file (a.k.a: icon, region and extra config) to embed
    \\<in>                   The elf file to process
    \\<out>                  The output 3dsx file to write
    \\
);

pub fn main() !u8 {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    const stderr_writer = std.io.getStdErr().writer();

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &cli_params, named_parsers, .{
        .diagnostic = &diag,
        .allocator = alloc,
    }) catch |err| {
        // Report useful error and exit.
        diag.report(stderr_writer, err) catch {};
        return 1;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null or res.positionals[1] == null) {
        std.debug.print(\\ zitrus - convert-3dsx
                        \\ converts a supported elf file to 3dsx
                        \\
                        \\
                        , .{});
        try clap.help(stderr_writer, clap.Help, &cli_params, .{});
        return 0;
    }

    // TODO: Handle RomFS and SMDH
    if (res.args.smdh != null or res.args.romfs != null) {
        @panic("TODO");
    }

    const in = res.positionals[0] orelse unreachable;
    const out = res.positionals[1] orelse unreachable;

    const cwd = std.fs.cwd();
    const input_file = cwd.openFile(in, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Input file '{s}' not found\n", .{in});
            return 1;
        },
        else => {
            std.debug.print("Could not open input file '{s}': {s}", .{in, @errorName(err)});
            return 1;
        },
    };

    defer input_file.close();

    const input_stat = try input_file.stat();

    const output_file = cwd.createFile(out, .{}) catch |err| {
        std.debug.print("Could not create/open output file '{s}' for writing: {s}", .{out, @errorName(err)}); 
        return 1;
    };
    defer output_file.close();

    var output_buffered = std.io.bufferedWriter(output_file.writer());

    const input_elf = try input_file.readToEndAllocOptions(alloc, input_stat.size, input_stat.size, @alignOf(usize), null);
    defer alloc.free(input_elf);

    zitrus_tooling.@"3dsx".processElf(output_buffered.writer(), input_elf) catch |err| switch(err) {
        error.InvalidMachine => {
            std.debug.print("Error processing elf: The elf machine is not ARM\n", .{});
            return 1;
        },
        error.NotExecutable => {
            std.debug.print("Error processing elf: The elf is not executable\n", .{});
            return 1;
        },
        error.InvalidEntryAddress => {
            std.debug.print("Error processing elf: The entry address is not the base address of the .text segment\n", .{});
            return 1;
        },
        error.UnalignedSegmentMemory => {
            std.debug.print("Error processing elf: Segment memory is not aligned to ARM word alignment (4 bytes)\n", .{});
            return 1;
        },
        error.UnalignedSegmentFileMemory => {
            std.debug.print("Error processing elf: Segment file memory is not aligned to ARM word alignment (4 bytes)\n", .{});
            return 1;
        },
        error.NonContiguousSegment => {
            std.debug.print("Error processing elf: Non-continuous segments\n", .{});
            return 1;
        },
        error.CodeSegmentMustBeFirst => {
            std.debug.print("Error processing elf: The .text/.code segment must be the first to appear\n", .{});
            return 1;
        },
        error.RodataSegmentMustBeSecond => {
            std.debug.print("Error processing elf: The .rodata segment must be the second to appear or not appear at all\n", .{});
            return 1;
        },
        error.DataSegmentMustBeLast => {
            std.debug.print("Error processing elf: The .data segment must be the last segment to appear\n", .{});
            return 1;
        },
        error.NonDataSegmentHasBss => {
            std.debug.print("Error processing elf: Non .data segment has bss\n", .{});
            return 1;
        },
        error.InvalidSegment => {
            std.debug.print("Error processing elf: More usable segments than expected\n", .{});
            return 1;
        },
        else => {
            std.debug.print("Could not process elf: {s}\n", .{@errorName(err)});
            return 1;
        }
    };

    try output_buffered.flush();
    return 0;
}

const std = @import("std");
const clap = @import("clap");
const zitrus_tooling = @import("zitrus-tooling");
