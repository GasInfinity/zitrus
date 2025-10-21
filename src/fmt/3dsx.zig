//! The defacto format for Nintendo 3DS Homebrew executables.
//!
//! Based on the documentation found in 3dbrew: https://3dbrew.org/wiki/3DSX_Format

pub const magic = "3DSX";

pub const Header = extern struct {
    magic: [magic.len]u8 = magic.*,
    header_size: u16,
    relocation_header_size: u16,
    version: u32,
    flags: u32,
    text_segment_size: u32,
    rodata_segment_size: u32,
    data_segment_size: u32,
    bss_segment_size: u32,

    pub const CheckError = error{ Not3dsx, UnrecognizedHeaderSize, UnrecognizedVersion, InvalidTextSegment, InvalidDataSegment };
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.Not3dsx;
        if (hdr.header_size != @sizeOf(Header) and hdr.header_size != @sizeOf(Header) + @sizeOf(ExtendedHeader)) return error.UnrecognizedHeaderSize;
        if (hdr.version != 0) return error.UnrecognizedVersion;
        if (hdr.text_segment_size == 0) return error.InvalidTextSegment;
        if (hdr.bss_segment_size > hdr.data_segment_size) return error.InvalidDataSegment;
    }
};

pub const ExtendedHeader = extern struct { smdh_offset: u32, smdh_size: u32, romfs_offset: u32 };

pub const RelocationHeader = extern struct {
    absolute_relocations: u32,
    relative_relocations: u32,
};

pub const Relocation = extern struct {
    words_to_skip: u16,
    words_to_patch: u16,
};

pub const MakeOptions = struct {
    smdh: ?smdh.Smdh = null,
    romfs: ?*std.Io.Reader = null,
};

/// Makes a 3dsx from a binary, a SMDH and a RomFS
///
/// Asserts that the `text` segment address is the base address and entrypoint, the segments are sequential,
/// and that the only segment with differing file/memory sizes is `data`.
pub fn make(writer: *std.Io.Writer, reader: *std.fs.File.Reader, info: code.Info, gpa: std.mem.Allocator, options: MakeOptions) !void {
    std.debug.assert(info.findNonSequentialSegment() == null);
    std.debug.assert(info.findNonDataSegmentWithBss() == null);

    // They may be sorted already but we never know...
    std.mem.sort(u32, info.relocations.items, {}, comptime std.sort.asc(u32));

    var processed_relocations = try processRelocations(info, gpa);
    defer {
        var it = processed_relocations.iterator();

        while (it.next()) |relocs| {
            relocs.value.deinit(gpa);
        }
    }

    const header_size: u16 = if (options.smdh != null or options.romfs != null) @sizeOf(Header) + @sizeOf(ExtendedHeader) else @sizeOf(Header);

    const base_address = info.segments.get(.text).?.address;
    const text_size = info.segments.get(.text).?.memory_size;
    const rodata_size = if (info.segments.get(.rodata)) |rodata| rodata.memory_size else 0;
    const data_size, const bss_size = if (info.segments.get(.data)) |data| .{ data.memory_size, data.memory_size - data.file_size } else .{ 0, 0 };

    try writer.writeStruct(Header{
        .header_size = header_size,
        .relocation_header_size = @sizeOf(RelocationHeader),
        .version = 0x0,
        .flags = 0x0,
        .text_segment_size = text_size,
        .rodata_segment_size = rodata_size,
        .data_segment_size = data_size,
        .bss_segment_size = bss_size,
    }, .little);

    if (header_size > @sizeOf(Header)) {
        const executable_end: u32 = @sizeOf(Header) + @sizeOf(ExtendedHeader) + (3 * @sizeOf(RelocationHeader)) + text_size + rodata_size + (data_size - bss_size) + (tot_reloc: {
            var total: u32 = 0;

            for (std.enums.values(code.Segment)) |segment| {
                total += @intCast(@sizeOf(Relocation) * processed_relocations.get(segment).items.len);
            }

            break :tot_reloc total;
        });

        var current_end = executable_end;
        try writer.writeStruct(ExtendedHeader{
            .smdh_offset = current_end,
            .smdh_size = (if (options.smdh != null) size: {
                current_end += @sizeOf(smdh.Smdh);
                break :size @sizeOf(smdh.Smdh);
            } else 0),
            .romfs_offset = current_end,
        }, .little);
    }

    for (std.enums.values(code.Segment)) |segment| {
        try writer.writeStruct(RelocationHeader{
            .absolute_relocations = @intCast(processed_relocations.get(segment).items.len),
            .relative_relocations = 0,
        }, .little);
    }

    var info_rw = info;
    var segment_it = info_rw.segments.iterator();
    while (segment_it.next()) |seg| {
        const segment_relocs = processed_relocations.get(seg.key);

        var patched: usize = 0;

        try reader.seekTo(seg.value.file_offset);
        for (segment_relocs.items) |rc| {
            try reader.interface.streamExact(writer, rc.words_to_skip * @sizeOf(u32));

            for (0..rc.words_to_patch) |_| {
                const addend = try reader.interface.takeInt(u32, .little);

                try writer.writeInt(u32, (addend - base_address), .little);
            }

            patched += (rc.words_to_skip + @as(usize, rc.words_to_patch)) * @sizeOf(u32);
        }

        try reader.interface.streamExact(writer, (seg.value.file_size - patched));
    }

    for (std.enums.values(code.Segment)) |segment| {
        for (processed_relocations.get(segment).items) |reloc| {
            try writer.writeStruct(reloc, .little);
        }
    }

    if (options.smdh) |smdh_data| {
        try writer.writeStruct(smdh_data, .little);
    }

    if (options.romfs) |romfs| {
        _ = try romfs.streamRemaining(writer);
    }
}

fn processRelocations(info: code.Info, gpa: std.mem.Allocator) !std.EnumArray(code.Segment, std.ArrayList(Relocation)) {
    var processed: std.EnumArray(code.Segment, std.ArrayList(Relocation)) = .initFill(.empty);
    errdefer {
        var it = processed.iterator();
        while (it.next()) |relocs| {
            relocs.value.deinit(gpa);
        }
    }

    const text, const text_size = .{ info.segments.get(.text).?.address, info.segments.get(.text).?.memory_size };
    const rodata, const rodata_size = if (info.segments.get(.rodata)) |rodata| .{ rodata.address, rodata.memory_size } else .{ text + text_size, 0 };
    const data, const data_size = if (info.segments.get(.data)) |data| .{ data.address, data.memory_size } else .{ rodata + rodata_size, 0 };
    const top = data + data_size;

    const base_addresses: []const u32 = &.{ text, rodata, data, top };

    var last_relocation_address: u32 = text;
    var current_base: u8 = 0;

    const relocs = info.relocations.items;

    // NOTE: relocations are already sorted
    var current_absolute: usize = 0;

    finish_relocations: while (current_absolute < relocs.len) {
        while (relocs[current_absolute] >= base_addresses[current_base + 1]) {
            current_base += 1;

            if (current_base >= 3) break :finish_relocations;

            last_relocation_address = base_addresses[current_base];
        }

        const current_processed: *std.ArrayList(Relocation) = processed.getPtr(@enumFromInt(current_base));
        var skipped_words: usize = @divExact(relocs[current_absolute] - last_relocation_address, @sizeOf(u32));

        while (skipped_words > std.math.maxInt(u16)) : (skipped_words -= std.math.maxInt(u16)) {
            try current_processed.append(gpa, Relocation{
                .words_to_skip = std.math.maxInt(u16),
                .words_to_patch = 0,
            });
        }

        var sequential_patches: usize = 0;
        var current = relocs[current_absolute];
        var last = current;
        // NOTE: Alignment was already checked before
        while (current < base_addresses[current_base + 1] and (current - last) <= 4) {
            sequential_patches += 1;
            current_absolute += 1;

            last = current;

            if (current_absolute == relocs.len) {
                break;
            }

            current = relocs[current_absolute];
        }

        while (sequential_patches > std.math.maxInt(u16)) : (sequential_patches -= std.math.maxInt(u16)) {
            try current_processed.append(gpa, Relocation{
                .words_to_skip = @intCast(skipped_words),
                .words_to_patch = std.math.maxInt(u16),
            });

            skipped_words = 0;
        }

        try current_processed.append(gpa, Relocation{
            .words_to_skip = @intCast(skipped_words),
            .words_to_patch = @intCast(sequential_patches),
        });

        last_relocation_address = last + @sizeOf(u32);
    }

    return processed;
}

const std = @import("std");
const elf = std.elf;

const zitrus = @import("zitrus");
const code = zitrus.fmt.code;
const smdh = zitrus.horizon.fmt.smdh;
