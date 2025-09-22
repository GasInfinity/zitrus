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
    code_segment_size: u32,
    rodata_segment_size: u32,
    data_segment_size: u32,
    bss_segment_size: u32,
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

pub const ElfConversionError = error{
    InvalidMachine,
    NotExecutable,
    InvalidEntryAddress,
    UnalignedSegmentMemory,
    UnalignedSegmentFileMemory,
    NonContiguousSegment,
    CodeSegmentMustBeFirst,
    RodataSegmentMustBeSecond,
    DataSegmentMustBeLast,
    NonDataSegmentHasBss,
    InvalidSegment,
};

// Taken from: https://kolegite.com/EE_library/standards/ARM_ABI/aaelf32.pdf
const R_ARM = enum(u32) {
    /// DATA S + A
    ABS32 = 2,
    /// ARM ((S + A) | T) – P
    CALL = 28,
    /// ARM ((S + A) | T) – P
    JUMP24 = 29,

    TLS_LE32 = 108,
    TLS_LE12 = 110,
    _,
};

const Segment = enum(u2) {
    code,
    rodata,
    data,

    pub inline fn next(segment: Segment) Segment {
        std.debug.assert(segment != .data);
        return @enumFromInt(@intFromEnum(segment) + 1);
    }
};

const SegmentData = struct {
    // code address is implicitly the base address also
    segment_addresses: [4]u32 = @splat(0),
    segment_offsets: std.EnumArray(Segment, u32) = .initFill(0),
    segment_sizes: std.EnumArray(Segment, u32) = .initFill(0),
    bss_size: u32 = 0,
};

const RelocationInfo = struct {
    absolute: std.ArrayList(u32) = .{},
    relative: std.ArrayList(u32) = .{},

    pub fn deinit(info: *RelocationInfo, allocator: std.mem.Allocator) void {
        info.absolute.deinit(allocator);
        info.relative.deinit(allocator);
    }
};

const ProcessedRelocations = struct {
    const Data = std.EnumArray(Segment, std.ArrayList(Relocation));

    absolute: Data = .initFill(.{}),
    relative: Data = .initFill(.{}),

    pub fn deinit(relocations: *ProcessedRelocations, allocator: std.mem.Allocator) void {
        inline for (comptime std.enums.values(Segment)) |segment| {
            relocations.absolute.getPtr(segment).deinit(allocator);
            relocations.relative.getPtr(segment).deinit(allocator);
        }
    }
};

pub const MakeOptions = struct {
    gpa: std.mem.Allocator,
    smdh: ?smdh.Smdh = null,
    romfs: ?*std.Io.Reader = null,
};

/// Makes a `3DSX` from an elf file and optionally `SMDH` and `RomFS` data.
pub fn make(in_elf: std.fs.File, out_3dsx: *std.Io.Writer, options: MakeOptions) !void {
    const elf_buff = buff: {
        var elf_reader_buf: [4096]u8 = undefined;
        var in_elf_reader = in_elf.reader(&elf_reader_buf);
        const elf_size = try in_elf_reader.getSize();
        const elf_buff = try options.gpa.alloc(u8, elf_size);
        try in_elf_reader.interface.readSliceAll(elf_buff);
        break :buff elf_buff;
    };
    defer options.gpa.free(elf_buff);

    const elf_header: elf.Elf32_Ehdr = std.mem.bytesToValue(elf.Elf32_Ehdr, elf_buff[0..@sizeOf(elf.Elf32_Ehdr)]);

    if (!std.mem.eql(u8, elf_header.e_ident[0..4], elf.MAGIC)) return error.InvalidElfMagic;
    if (elf_header.e_ident[elf.EI_VERSION] != 1) return error.InvalidElfVersion;
    if (elf_header.e_ident[elf.EI_CLASS] != 1 or elf_header.e_machine != .ARM) return error.InvalidMachine;
    if (elf_header.e_ident[elf.EI_DATA] != elf.ELFDATA2LSB) return error.InvalidElfEndian;
    if (std.mem.littleToNative(elf.ET, elf_header.e_type) != .EXEC) return error.NotExecutable;

    const segments: []const elf.Elf32_Phdr = @alignCast(std.mem.bytesAsSlice(elf.Elf32_Phdr, elf_buff[std.mem.littleToNative(u32, elf_header.e_phoff)..][0..(std.mem.littleToNative(u32, elf_header.e_phnum) * @sizeOf(elf.Elf32_Phdr))]));
    const segment_data = try processSegments(segments);

    if (elf_header.e_entry != segment_data.segment_addresses[@intFromEnum(Segment.code)]) return error.InvalidEntryAddress;

    const sections: []const elf.Elf32_Shdr = @alignCast(std.mem.bytesAsSlice(elf.Elf32_Shdr, elf_buff[std.mem.littleToNative(u32, elf_header.e_shoff)..][0..(std.mem.littleToNative(u32, elf_header.e_shnum) * @sizeOf(elf.Elf32_Shdr))]));

    var processed_relocations: ?ProcessedRelocations = relocs: {
        var relocations: RelocationInfo = try readModifyRelocations(elf_buff, segment_data, sections, options.gpa) orelse break :relocs null;
        defer relocations.deinit(options.gpa);

        break :relocs try processRelocations(segment_data, relocations, options.gpa);
    };
    defer if (processed_relocations) |*relocations| {
        relocations.deinit(options.gpa);
    };

    const header_size: u16 = if (options.smdh != null or options.romfs != null) @sizeOf(Header) + @sizeOf(ExtendedHeader) else @sizeOf(Header);

    try out_3dsx.writeStruct(Header{
        .header_size = header_size,
        .relocation_header_size = @sizeOf(RelocationHeader),
        .version = 0x0,
        .flags = 0x0,
        .code_segment_size = segment_data.segment_sizes.get(.code),
        .rodata_segment_size = segment_data.segment_sizes.get(.rodata),
        .data_segment_size = segment_data.segment_sizes.get(.data),
        .bss_segment_size = segment_data.bss_size,
    }, .little);

    if (header_size > @sizeOf(Header)) {
        const executable_end: u32 = @sizeOf(Header) + @sizeOf(ExtendedHeader) + (3 * @sizeOf(RelocationHeader)) + segment_data.segment_sizes.get(.code) + segment_data.segment_sizes.get(.rodata) + segment_data.segment_sizes.get(.data) - segment_data.bss_size + (if (processed_relocations) |relocs| tot: {
            var total: u32 = 0;
            inline for (comptime std.enums.values(Segment)) |segment| {
                inline for (&.{ relocs.absolute.get(segment).items, relocs.relative.get(segment).items }) |segment_relocs| {
                    total += @intCast(@sizeOf(Relocation) * segment_relocs.len);
                }
            }

            break :tot total;
        } else 0);

        var current_end = executable_end;
        try out_3dsx.writeStruct(ExtendedHeader{
            .smdh_offset = current_end,
            .smdh_size = (if (options.smdh != null) size: {
                current_end += @sizeOf(smdh.Smdh);
                break :size @sizeOf(smdh.Smdh);
            } else 0),
            .romfs_offset = current_end,
        }, .little);
    }

    if (processed_relocations) |relocs| {
        inline for (comptime std.enums.values(Segment)) |segment| {
            try out_3dsx.writeStruct(RelocationHeader{
                .absolute_relocations = @intCast(relocs.absolute.get(segment).items.len),
                .relative_relocations = @intCast(relocs.relative.get(segment).items.len),
            }, .little);
        }
    } else inline for (comptime std.enums.values(Segment)) |_| {
        try out_3dsx.writeStruct(std.mem.zeroes(RelocationHeader), .little);
    }

    for (std.enums.values(Segment)) |segment| {
        const offset = segment_data.segment_offsets.get(segment);

        if (offset == 0) {
            continue;
        }

        const size = segment_data.segment_sizes.get(segment) - (if (segment == .data) segment_data.bss_size else 0);

        try out_3dsx.writeAll(elf_buff[offset..][0..size]);
    }

    if (processed_relocations) |relocs| {
        inline for (comptime std.enums.values(Segment)) |segment| {
            inline for (&.{ relocs.absolute.get(segment).items, relocs.relative.get(segment).items }) |segment_relocs| {
                for (segment_relocs) |reloc| {
                    try out_3dsx.writeStruct(reloc, .little);
                }
            }
        }
    }

    if (options.smdh) |smdh_data| {
        try out_3dsx.writeStruct(smdh_data, .little);
    }

    if (options.romfs) |romfs| {
        _ = try romfs.streamRemaining(out_3dsx);
    }
}

fn processSegments(segments: []const elf.Elf32_Phdr) ElfConversionError!SegmentData {
    const ElfSegmentConversionState = union(enum) {
        waiting_code_segment,
        waiting_rodata_or_data_segment,
        waiting_data_segment,
        finished,
    };

    var segment_state: ElfSegmentConversionState = .waiting_code_segment;
    var segment_data: SegmentData = std.mem.zeroes(SegmentData);

    for (segments) |segment| {
        const segment_type = std.mem.littleToNative(u32, segment.p_type);
        const mem_size = std.mem.littleToNative(u32, segment.p_memsz);

        if (segment_type != elf.PT_LOAD or mem_size == 0) {
            continue;
        }

        if (!std.mem.isAligned(mem_size, 4)) {
            return error.UnalignedSegmentMemory;
        }

        const file_size = std.mem.littleToNative(u32, segment.p_filesz);
        const flags = std.mem.littleToNative(u32, segment.p_flags);

        if (mem_size != file_size and flags != (elf.PF_R | elf.PF_W)) {
            return error.NonDataSegmentHasBss;
        }

        const vaddr = std.mem.littleToNative(u32, segment.p_vaddr);
        const offset = std.mem.littleToNative(u32, segment.p_offset);
        const handled_segment: Segment = st: switch (segment_state) {
            .waiting_code_segment => {
                if (flags != (elf.PF_R | elf.PF_X)) {
                    return error.CodeSegmentMustBeFirst;
                }

                segment_state = .waiting_rodata_or_data_segment;
                break :st .code;
            },
            .waiting_rodata_or_data_segment => {
                if (flags == (elf.PF_R | elf.PF_W)) {
                    continue :st .waiting_data_segment;
                }

                if (flags != elf.PF_R) {
                    return error.RodataSegmentMustBeSecond;
                }

                if (vaddr != segment_data.segment_addresses[3]) {
                    return error.NonContiguousSegment;
                }

                segment_state = .waiting_data_segment;
                break :st .rodata;
            },
            .waiting_data_segment => {
                if (flags != (elf.PF_R | elf.PF_W)) {
                    return error.DataSegmentMustBeLast;
                }

                if (vaddr != segment_data.segment_addresses[3]) {
                    return error.NonContiguousSegment;
                }

                segment_data.bss_size = (mem_size - file_size);
                segment_state = .finished;
                break :st .data;
            },
            .finished => return error.InvalidSegment,
        };

        segment_data.segment_addresses[@intFromEnum(handled_segment)] = vaddr;
        segment_data.segment_offsets.set(handled_segment, offset);
        segment_data.segment_sizes.set(handled_segment, mem_size);
        segment_data.segment_addresses[3] = std.mem.alignForward(u32, vaddr + mem_size, 4096);
    }

    return segment_data;
}

// As calls in ARM are PC-relative with 24-bits, they DON'T need to be relocated due to how the 3dsx is loaded (Only the base address changes)
// You'd say that that's obvious because there's only absolute and relative relocation headers, but the more you know, the better.
// Now, I don't know how relative relocations work so I'll only process absolute ones (zig has not made any yet)
// TODO: Implement relative relocations when needed.
fn readModifyRelocations(elf_buffer: []u8, segment_data: SegmentData, sections: []const elf.Elf32_Shdr, allocator: std.mem.Allocator) !?RelocationInfo {
    const has_relocations = v: for (sections) |section| switch (std.mem.littleToNative(u32, section.sh_type)) {
        elf.SHT_REL => break :v true,
        elf.SHT_RELA => return error.InvalidRelocationSection,
        else => continue,
    } else false;

    if (!has_relocations) {
        return null;
    }

    const base_addr = segment_data.segment_addresses[0];

    var relocation_info: RelocationInfo = .{ .absolute = try std.ArrayList(u32).initCapacity(allocator, 32) };
    errdefer relocation_info.deinit(allocator);

    for (sections) |section| {
        switch (std.mem.littleToNative(u32, section.sh_type)) {
            elf.SHT_REL => {
                const target_section: elf.Elf32_Shdr = sections[std.mem.littleToNative(u32, section.sh_info)];
                const target_flags = std.mem.littleToNative(u32, target_section.sh_flags);

                if ((target_flags & elf.SHF_ALLOC) == 0) {
                    // Do nothing if the section is not even loaded
                    continue;
                }

                const vaddr_start = std.mem.littleToNative(u32, target_section.sh_addr);
                const size = std.mem.littleToNative(u32, target_section.sh_size);
                const section_data: []u8 = elf_buffer[std.mem.littleToNative(u32, target_section.sh_offset)..][0..size];

                const relocations: []const elf.Elf32_Rel = @alignCast(std.mem.bytesAsSlice(elf.Elf32_Rel, elf_buffer[std.mem.littleToNative(u32, section.sh_offset)..][0..std.mem.littleToNative(u32, section.sh_size)]));

                for (relocations) |relocation| {
                    const info = std.mem.littleToNative(u32, relocation.r_info);
                    const r_type: R_ARM = @enumFromInt(@as(u8, @truncate(info)));
                    const vaddr = std.mem.littleToNative(u32, relocation.r_offset);

                    switch (r_type) {
                        // These are already PC-relative
                        .CALL, .JUMP24 => {},
                        // Same, but `$tp` relative
                        .TLS_LE32, .TLS_LE12 => {},
                        .ABS32 => {
                            if (!std.mem.isAligned(vaddr, @alignOf(u32))) {
                                return error.UnalignedAbsoluteRelocation;
                            }

                            if (vaddr < base_addr or vaddr >= (base_addr + size)) {
                                continue;
                            }

                            const relative = vaddr - vaddr_start;
                            const section_value: *u32 = @alignCast(std.mem.bytesAsValue(u32, section_data[relative..][0..4]));
                            const value = section_value.*;

                            if (value < base_addr) {
                                // XXX: Maybe we could ignore these?
                                log.err("relocation in '0x{X}' contains invalid value 0x{X} (< 0x{X})", .{ vaddr, value, base_addr });
                                return error.InvalidAbsoluteRelocation;
                            }

                            try relocation_info.absolute.append(allocator, vaddr);
                            section_value.* = std.mem.nativeToLittle(u32, (value - base_addr));
                        },
                        else => {
                            log.err("unhandled relocation type: {}", .{r_type});
                            return error.UnknownRelocation;
                        },
                    }
                }
            },
            // 3dsx doesn't support relocations with addends
            elf.SHT_RELA => return error.InvalidRelocationSection,
            else => {},
        }
    }

    std.mem.sort(u32, relocation_info.absolute.items, {}, comptime std.sort.asc(u32));
    return relocation_info;
}

fn processRelocations(segment_data: SegmentData, relocation_info: RelocationInfo, allocator: std.mem.Allocator) !ProcessedRelocations {
    var relocations: ProcessedRelocations = .{};

    inline for (&.{ &relocations.absolute, &relocations.relative }, &.{ relocation_info.absolute.items, relocation_info.relative.items }) |*processed, relocs| {
        var last_relocation_address: u32 = segment_data.segment_addresses[0];
        var current_segment: Segment = .code;

        // NOTE: relocations are sorted by readModifyRelocations!
        var current_absolute: usize = 0;

        while (current_absolute < relocs.len) {
            while (relocs[current_absolute] >= segment_data.segment_addresses[@intFromEnum(current_segment) + 1]) {
                current_segment = current_segment.next();
                last_relocation_address = segment_data.segment_addresses[@intFromEnum(current_segment)];
            }

            const current_processed: *std.ArrayList(Relocation) = processed.*.getPtr(current_segment);
            var skipped_words: usize = @divExact(relocs[current_absolute] - last_relocation_address, @sizeOf(u32));

            while (skipped_words > std.math.maxInt(u16)) : (skipped_words -= std.math.maxInt(u16)) {
                try current_processed.append(allocator, Relocation{
                    .words_to_skip = std.math.maxInt(u16),
                    .words_to_patch = 0,
                });
            }

            var sequential_patches: usize = 0;
            var current = relocs[current_absolute];
            var last = current;
            // NOTE: Alignment was already checked before
            while (current < segment_data.segment_addresses[@intFromEnum(current_segment) + 1] and (current - last) <= 4) {
                sequential_patches += 1;
                current_absolute += 1;

                last = current;

                if (current_absolute == relocs.len) {
                    break;
                }

                current = relocs[current_absolute];
            }

            while (sequential_patches > std.math.maxInt(u16)) : (sequential_patches -= std.math.maxInt(u16)) {
                try current_processed.append(allocator, Relocation{
                    .words_to_skip = @intCast(skipped_words),
                    .words_to_patch = std.math.maxInt(u16),
                });

                skipped_words = 0;
            }

            try current_processed.append(allocator, Relocation{
                .words_to_skip = @intCast(skipped_words),
                .words_to_patch = @intCast(sequential_patches),
            });

            last_relocation_address = last + @sizeOf(u32);
        }
    }

    return relocations;
}

const std = @import("std");
const elf = std.elf;

const zitrus = @import("zitrus");
const smdh = zitrus.horizon.fmt.smdh;

const log = std.log.scoped(.@"3dsx");
