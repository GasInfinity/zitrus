pub const description = "Make a 3DS firmware file from 4 raw/elf sections.";

pub const descriptions = .{
    .boot_priority = "Higher values have more priority",
    .arm9_entry = "ARM9 entrypoint, if none an arm9 elf must be specified",
    .arm11_entry = "ARM11 entrypoint, if none an arm11 elf must be specified",
    .section = "Section to add to the firm",
    .output = "Output file, if none stdout is used",
};

pub const switches = .{
    .boot_priority = 'p',
    .elf = 'e',
    .section = 's',
    .output = 'o',
    .verbose = 'v',
};

const ElfSection = struct {
    pub const Kind = enum { raw, arm9, arm11 };
    pub const descriptions = .{
        .path = "Path to the file",
        .kind = "Whether the elf is raw, arm9 or arm11",
        .method = "Copy method to use",
    };

    path: []const u8,
    kind: Kind,
    method: firm.Section.CopyMethod,
};

pub const Section = struct {
    pub const descriptions = .{
        .path = "Path to the file",
        .address = "Load address of the file",
        .method = "Copy method to use when loading",
    };

    path: []const u8,
    address: u32,
    method: firm.Section.CopyMethod,
};

boot_priority: u32 = 0,
arm9_entry: u32 = 0,
arm11_entry: u32 = 0,
elf: zdap.BoundedArray(ElfSection, 4) = .empty,
section: zdap.BoundedArray(Section, 4) = .empty,
verbose: bool,

output: ?[]const u8,

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(&output_buffer);
    const out = &output_writer.interface;

    var current_offset: u32 = @sizeOf(firm.Header);
    var hdr: firm.Header = .{
        .boot_priority = args.boot_priority,
        .arm11_entry = args.arm11_entry,
        .arm9_entry = args.arm9_entry,
        .sections = std.mem.zeroes([4]firm.Section),
        .signature = @splat(0),
    };

    var file_data: zdap.BoundedArray([]const u8, 4) = .empty;
    defer for (file_data.constSlice()) |data| arena.free(data);

    if (args.section.len + args.elf.len > 4) {
        log.err("too many sections specified", .{});
        return 1;
    }

    var has_arm11_elf, var has_arm9_elf = .{ false, false };
    for (args.elf.constSlice()) |elf| switch (elf.kind) {
        .raw => {},
        .arm9, .arm11 => |k| {
            const has_elf, const entry = .{ if (k == .arm9) &has_arm9_elf else &has_arm11_elf, if (k == .arm9) hdr.arm9_entry else hdr.arm11_entry };

            if (entry != 0) {
                log.err("confusing arguments, specified --{t}-entry and {t} elf", .{ k, k });
                log.err("either set the elf as 'raw' or drop the --{t}-entry", .{k});
                return 1;
            } else if (!has_elf.*) {
                has_elf.* = true;
            } else if (has_elf.*) {
                log.err("too many {t} elf's specified", .{k});
                return 1;
            }
        },
    };

    var i: u8 = 0;
    for (args.elf.constSlice()) |elf| {
        defer i += 1;

        var elf_result = ElfResult.init(cwd, elf, arena) catch |err| {
            log.err("could not process {t} elf '{s}': {t}", .{ elf.kind, elf.path, err });
            return 1;
        };
        defer elf_result.info.deinit(arena);
        errdefer arena.free(elf_result.data);

        const file_offset = current_offset;
        const safe_size: u32 = @intCast(elf_result.data.len);

        // NOTE: elf_result.data.len cannot be larger than u32 as we always read 32-bit elfs.
        current_offset = std.math.add(u32, current_offset, safe_size) catch {
            log.err("could not make firm, sum of all sections overflows an u32!", .{});
            return 1;
        };

        hdr.sections[i] = .{
            .offset = file_offset,
            .address = elf_result.info.segments[0].physical_address,
            .size = safe_size,
            .copy_method = elf.method,
            .hash = undefined,
        };

        switch (elf.kind) {
            .arm11 => hdr.arm11_entry = elf_result.info.entrypoint,
            .arm9 => hdr.arm9_entry = elf_result.info.entrypoint,
            else => {},
        }

        if (args.verbose) {
            log.info("ELF", .{});
            log.info("  Entry: 0x{X:0>8} | {t}", .{ elf_result.info.entrypoint, elf.kind });
            log.info("  Loadable segments: {}", .{elf_result.info.segments.len});
            log.info("  LMA Base: 0x{X:0>8}", .{hdr.sections[i].address});
            log.info("  LMA Top: 0x{X:0>8}", .{hdr.sections[i].address + hdr.sections[i].size});
        }

        std.crypto.hash.sha2.Sha256.hash(elf_result.data, &hdr.sections[i].hash, .{});
        file_data.appendAssumeCapacity(elf_result.data);
    }

    for (args.section.constSlice()) |section| {
        defer i += 1;
        const file = cwd.openFile(section.path, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ section.path, err });
            return 1;
        };
        errdefer file.close();

        var reader = file.reader(&.{});
        const size = try reader.getSize();

        // NOTE: Arbitrary, even an u31 is 100% invalid.
        if (size > std.math.maxInt(u31)) {
            log.err("could not make firm as file '{s}' has a size of {} bytes, larger than an u31!", .{ section.path, size });
            return 1;
        }

        const safe_size: u32 = std.mem.alignForward(u32, @intCast(size), 512);
        const file_offset = current_offset;

        current_offset = std.math.add(u32, current_offset, safe_size) catch {
            log.err("could not make firm, sum of all sections overflows an u32!", .{});
            return 1;
        };

        const data = try arena.alloc(u8, size);
        file_data.appendAssumeCapacity(data);

        try reader.interface.readSliceAll(data);

        hdr.sections[i] = .{
            .offset = file_offset,
            .address = section.address,
            .size = safe_size,
            .copy_method = section.method,
            .hash = undefined,
        };

        if (args.verbose) {
            log.info("RAW", .{});
            log.info("  LMA Base: 0x{X:0>8}", .{hdr.sections[i].address});
            log.info("  LMA Top: 0x{X:0>8}", .{hdr.sections[i].address + hdr.sections[i].size});
        }
        std.crypto.hash.sha2.Sha256.hash(data, &hdr.sections[i].hash, .{});
    }

    if (current_offset >= 6 * 1024 * 1024) log.warn("resulting FIRM is larger than 6MB, here be dragons...", .{});

    // TODO: Signature?

    try out.writeStruct(hdr, .little);
    try out.writeVecAll(file_data.slice());
    try out.flush();
    return 0;
}

pub const ElfResult = struct {
    info: code.Info,
    data: []const u8,

    pub fn init(cwd: std.fs.Dir, section: ElfSection, gpa: std.mem.Allocator) !ElfResult {
        const elf_file = try cwd.openFile(section.path, .{ .mode = .read_only });
        defer elf_file.close();

        var elf_reader_buf: [4096]u8 = undefined;
        var elf_reader = elf_file.reader(&elf_reader_buf);

        var info = try code.Info.extractStaticElfAlloc(&elf_reader, gpa);
        errdefer info.deinit(gpa);

        if (info.segments.len == 0) {
            log.err("no loadable segments could be found", .{});
            return error.InvalidElf;
        }

        if (info.findNonSequentialPhysicalSegment(.fromByteUnits(4))) |first_non_sequential| {
            log.err("segment {} is not sequential in memory!", .{first_non_sequential});
            return error.InvalidElf;
        }

        if (info.findSegmentWithBss()) |first_bss| if (first_bss != info.segments.len - 1) {
            log.err("non-final segment {} has bss", .{first_bss});
            return error.InvalidElf;
        };

        var data: std.Io.Writer.Allocating = .init(gpa);
        defer data.deinit();

        try info.alignedStream(&data.writer, &elf_reader, .fromByteUnits(4));

        const written = data.written();

        try data.writer.splatByteAll(undefined, std.mem.alignForward(usize, written.len, firm.Section.min_alignment) - written.len);

        return .{
            .info = info,
            .data = try data.toOwnedSlice(),
        };
    }
};

const Make = @This();
const log = std.log.scoped(.firm);

const zdap = @import("zdap");

const std = @import("std");
const zitrus = @import("zitrus");

const code = zitrus.fmt.code;
const firm = zitrus.fmt.firm;
