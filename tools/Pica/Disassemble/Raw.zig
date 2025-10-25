pub const description = "Disassemble RAW instructions with and without operand descriptors.";

pub const descriptions = .{
    .output = "Output file, if none stdout is used",
    .descriptors = "File containing raw operand descriptors, can be none but the output will be severely limited",
};

pub const switches = .{
    .output = 'o',
    .descriptors = 'd',
};

descriptors: ?[]const u8,
output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Raw, arena: std.mem.Allocator) !u8 {
    _ = arena;
    const cwd = std.fs.cwd();

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(&input_buffer);
    const in = &input_reader.interface;

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(&output_buffer);
    const out = &output_writer.interface;

    var descriptors_buffer: [128]OperandDescriptor = undefined;
    const descriptors: []const OperandDescriptor = if (args.descriptors) |desc| blk: {
        const descriptors_file = cwd.openFile(desc, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ desc, err });
            return 1;
        };
        defer descriptors_file.close();

        var descriptors_reader = descriptors_file.reader(&.{});
        const bytes_read = try descriptors_reader.interface.readSliceShort(@ptrCast(&descriptors_buffer));

        if (!std.mem.isAligned(bytes_read, @sizeOf(OperandDescriptor))) {
            log.warn("we've read {} bytes of operand descriptors which is NOT aligned to 4, truncating to {} bytes", .{ bytes_read, (bytes_read >> 2) << 2 });
        }

        const descriptors = descriptors_buffer[0..(bytes_read >> 2)];
        for (descriptors) |*descriptor| descriptor.* = @bitCast(@byteSwap(@as(u32, @bitCast(descriptor.*))));
        break :blk descriptors;
    } else blk: {
        break :blk &.{};
    };

    try out.print("; RAW PICA200 instruction stream\n", .{});
    try out.print("; Unknown/Invalid instructions may be found, beware!\n", .{});
    try out.writeByte('\n');

    var i: u13 = 0;
    while (true) : (i += 1) {
        const instruction: Instruction = @bitCast(in.takeInt(u32, .little) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        });

        try out.print("L_{X:0>3}: {f}\n", .{ i, instruction.fmtDisassemble(descriptors) });

        if (i >= std.math.maxInt(u12)) {
            log.err("instruction stream is too big! (> 4096 instructions)", .{});
            break;
        }
    }

    try out.flush();
    _ = try in.discardRemaining();
    return 0;
}

const Raw = @This();

const log = std.log.scoped(.pica);

const std = @import("std");
const zitrus = @import("zitrus");

const pica = zitrus.hardware.pica;
const shader = pica.shader;
const Instruction = shader.encoding.Instruction;
const OperandDescriptor = shader.encoding.OperandDescriptor;
const Component = shader.encoding.Component;
