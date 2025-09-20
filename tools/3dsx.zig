pub const description = "Make / Dump 3DSX files with an executable, SMDH and RomFS";

const Subcommand = enum { make };

pub const Make = struct {
    pub const description = "Convert an executable, SMDH and RomFS -> 3DSX";
    pub const descriptions = .{ .smdh = "SMDH metadata to embed", .romfs = "Rom filesystem to embed" };

    pub const switches = .{
        .smdh = 's',
        .romfs = 'r',
    };

    smdh: ?[]const u8,
    romfs: ?[]const u8,

    @"--": struct {
        pub const descriptions = .{
            .@"in.elf" = "Executable to convert",
            .@"out.3dsx" = "Output 3DSX filename",
        };

        @"in.elf": []const u8,
        @"out.3dsx": []const u8,
    },
};

@"-": union(Subcommand) {
    make: Make,
},

pub fn main(args: @"3dsx", arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    return switch (args.@"-") {
        .make => |make| m: {
            if (make.romfs) |_| {
                @panic("TODO: romfs in 3dsx");
            }

            const in_path = make.@"--".@"in.elf";
            const out_path = make.@"--".@"out.3dsx";

            const input_file = cwd.openFile(in_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open input executable '{s}': {s}\n", .{ in_path, @errorName(err) });
                break :m 1;
            };
            defer input_file.close();

            const smdh_data = if (make.smdh) |smdh_path| data: {
                const smdh_file = cwd.openFile(smdh_path, .{ .mode = .read_only }) catch |err| {
                    std.debug.print("could not open smdh file '{s}': {s}\n", .{ smdh_path, @errorName(err) });
                    break :m 1;
                };

                var buf: [@sizeOf(smdh.Smdh)]u8 = undefined;
                var smdh_reader = smdh_file.reader(&buf);
                const smdh_data: smdh.Smdh = smdh_reader.interface.peekStruct(smdh.Smdh, .little) catch |err| {
                    std.debug.print("could not read smdh file '{s}': {s}\n", .{ smdh_path, @errorName(err) });
                    break :m 1;
                };

                if (!std.mem.eql(u8, &smdh_data.magic, smdh.magic_value)) {
                    std.debug.print("smdh file '{s}' is invalid/corrupted\n", .{smdh_path});
                    break :m 1;
                }

                break :data smdh_data;
            } else null;

            const output_file = cwd.createFile(out_path, .{}) catch |err| {
                std.debug.print("could not create/open output file '{s}' for writing: {s}\n", .{ out_path, @errorName(err) });
                break :m 1;
            };
            defer output_file.close();

            var output_buffer: [8192]u8 = undefined;
            var output_writer = output_file.writer(&output_buffer);

            zitrus.fmt.@"3dsx".make(input_file, &output_writer.interface, .{
                .gpa = arena,
                .smdh = smdh_data,
            }) catch |err| switch (err) {
                error.InvalidMachine => {
                    std.debug.print("elf machine is not ARM!\n", .{});
                    break :m 1;
                },
                error.NotExecutable => {
                    std.debug.print("elf is not an executable!\n", .{});
                    break :m 1;
                },
                error.InvalidEntryAddress => {
                    std.debug.print("elf entry address is not the base address of the .text segment!\n", .{});
                    break :m 1;
                },
                error.UnalignedSegmentMemory => {
                    std.debug.print("elf segment memory is not aligned to ARM word alignment (4 bytes)!\n", .{});
                    break :m 1;
                },
                error.UnalignedSegmentFileMemory => {
                    std.debug.print("elf segment file memory is not aligned to ARM word alignment (4 bytes)!\n", .{});
                    break :m 1;
                },
                error.NonContiguousSegment => {
                    std.debug.print("elf non-contiguous segments\n", .{});
                    break :m 1;
                },
                error.CodeSegmentMustBeFirst => {
                    std.debug.print("elf .text/.code segment must be the first to appear\n", .{});
                    break :m 1;
                },
                error.RodataSegmentMustBeSecond => {
                    std.debug.print("elf .rodata segment must be the second to appear or not appear at all\n", .{});
                    break :m 1;
                },
                error.DataSegmentMustBeLast => {
                    std.debug.print("elf .data segment must be the last segment to appear\n", .{});
                    break :m 1;
                },
                error.NonDataSegmentHasBss => {
                    std.debug.print("elf .data segment has bss\n", .{});
                    break :m 1;
                },
                error.InvalidSegment => {
                    std.debug.print("elf has more usable segments than expected\n", .{});
                    break :m 1;
                },
                else => {
                    std.debug.print("elf could not be processed: {s}\n", .{@errorName(err)});
                    break :m 1;
                },
            };

            try output_writer.interface.flush();
            break :m 0;
        },
    };
}

const @"3dsx" = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const smdh = zitrus.horizon.fmt.smdh;
