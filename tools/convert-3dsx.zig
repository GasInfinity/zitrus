const params_help =
    \\-h, --help             Display this help and exit.
    \\-r, --romfs <str>      RomFS file (a.k.a: read-only filesystem that contains extra data) to embed
    \\-s, --smdh <str>       SMDH file (a.k.a: icon, region and extra config) to embed
    \\<str> 
    \\<str>
    \\
;

pub fn main() !u8 {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const params = comptime clap.parseParamsComptime(params_help);

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = alloc,
    }) catch |err| {
        // Report useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        std.debug.print(params_help, .{});
        return 0;
    }

    // TODO: Handle RomFS and SMDH
    if (res.args.smdh != null or res.args.romfs != null) {
        @panic("TODO");
    }

    const in = res.positionals[0] orelse unreachable;
    const out = res.positionals[1] orelse unreachable;

    const cwd = std.fs.cwd();
    const input_file = cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Could not open file: {s}\n", .{in});
                return 1;
            },
            else => return err,
        }
    };

    defer input_file.close();

    const input_stat = try input_file.stat();

    const output_file = try cwd.createFile(out, .{});
    defer output_file.close();

    var output_buffered = std.io.bufferedWriter(output_file.writer());

    const input_elf = try input_file.readToEndAllocOptions(alloc, input_stat.size, input_stat.size, @alignOf(usize), null);
    defer alloc.free(input_elf);

    zitrus_tooling.@"3dsx".processElf(output_buffered.writer(), input_elf) catch |err| {
        std.debug.print("Error processing elf: {s}\n", .{@errorName(err)});
        return 1;
    };

    try output_buffered.flush();
    return 0;
}

const std = @import("std");
const clap = @import("clap");
const zitrus_tooling = @import("zitrus-tooling");
