//! Extract code from different executable files for conversion purposes.
//!
//! Processes `Segment`s and extracts information from them.
//! Only one `Segment` type per executable is supported.
//!
//! Optionally and if the executable supports it,
//! extracts all relocation information.

pub const Segment = enum {
    pub const Data = struct {
        address: u32,
        file_offset: u32,
        file_size: u32,
        memory_size: u32,
    };

    text,
    rodata,
    data,

    pub fn elfFlags(segment: Segment) u32 {
        return switch (segment) {
            .text => elf.PF_R | elf.PF_X,
            .rodata => elf.PF_R,
            .data => elf.PF_R | elf.PF_W,
        };
    }
};

pub const Info = struct {
    entrypoint: u32,
    segments: std.EnumMap(Segment, Segment.Data),
    relocations: std.ArrayList(u32),

    pub fn deinit(info: *Info, gpa: std.mem.Allocator) void {
        info.relocations.deinit(gpa);
    }

    /// Returns the first non-sequential `Segment` or `null`
    pub fn findNonSequentialSegment(info: Info) ?Segment {
        var segments = info.segments; // https://github.com/ziglang/zig/issues/18769
        var it = segments.iterator();

        var last = (it.next() orelse return null).value.*;

        while (it.next()) |segment| {
            const next_address = std.mem.alignForward(usize, last.address + last.memory_size, 0x1000);

            if (next_address != segment.value.address) return segment.key;

            last = segment.value.*;
        }

        return null;
    }

    /// Returns the first non-data segment with bss.
    pub fn findNonDataSegmentWithBss(info: Info) ?Segment {
        var segments = info.segments; // https://github.com/ziglang/zig/issues/18769
        var it = segments.iterator();

        while (it.next()) |segment| {
            if (segment.key == .data) continue;
            if (segment.value.memory_size != segment.value.file_size) return segment.key;
        }

        return null;
    }
};

pub const ElfExtractError = error{
    NotElf,
    NotArm,
    NotLittleEndian,
    NotExecutable,
    DynamicallyLinked,
    DuplicatedSegment,
    InvalidRelocations,
    UnknownSegment,
} || std.fs.File.Reader.SeekError || std.Io.Reader.Error || std.mem.Allocator.Error;

const R_ARM_RELATIVE = 23;

pub fn extractStaticElfAlloc(reader: *std.fs.File.Reader, gpa: std.mem.Allocator) ElfExtractError!Info {
    const hdr: elf.Elf32_Ehdr = try reader.interface.takeStruct(elf.Elf32_Ehdr, .little);

    if (!std.mem.eql(u8, hdr.e_ident[0..4], elf.MAGIC)) return error.NotElf;
    if (hdr.e_ident[elf.EI_VERSION] != 1) return error.NotElf;
    if (hdr.e_ident[elf.EI_CLASS] != 1 or hdr.e_machine != .ARM) return error.NotArm;
    if (hdr.e_ident[elf.EI_DATA] != elf.ELFDATA2LSB) return error.NotLittleEndian;

    const et = std.mem.littleToNative(elf.ET, hdr.e_type);

    if (et != .EXEC and et != .DYN) return error.NotExecutable;

    var map: std.EnumMap(Segment, Segment.Data) = .init(.{});

    try reader.seekTo(hdr.e_phoff);
    next_segment: for (0..hdr.e_phnum) |_| {
        const phdr = try reader.interface.takeStruct(elf.Elf32_Phdr, .little);

        if (phdr.p_type == elf.PT_INTERP) return error.DynamicallyLinked;
        if (phdr.p_type != elf.PT_LOAD or phdr.p_memsz == 0) continue;

        for (std.enums.values(Segment)) |segment| {
            if (phdr.p_flags != segment.elfFlags()) {
                continue;
            }

            if (map.contains(segment)) {
                return error.DuplicatedSegment;
            }

            map.put(segment, .{
                .address = phdr.p_vaddr,
                .file_offset = phdr.p_offset,
                .file_size = phdr.p_filesz,
                .memory_size = phdr.p_memsz,
            });

            continue :next_segment;
        }

        return error.UnknownSegment;
    }

    try reader.seekTo(hdr.e_shoff);
    const maybe_rel_shdr: ?elf.Elf32_Shdr = rel_hdr: for (0..hdr.e_shnum) |_| {
        const shdr = try reader.interface.takeStruct(elf.Elf32_Shdr, .little);

        if (shdr.sh_type == elf.SHT_REL and (shdr.sh_flags & elf.SHF_ALLOC) != 0) break :rel_hdr shdr;
    } else null;

    const relocations: std.ArrayList(u32) = if (maybe_rel_shdr) |rel_shdr| relocs: {
        var relocations: std.ArrayList(u32) = .empty;
        errdefer relocations.deinit(gpa);

        if (rel_shdr.sh_size % @sizeOf(elf.Elf32_Rel) != 0) return error.InvalidRelocations;

        const rels_len = @divExact(rel_shdr.sh_size, @sizeOf(elf.Elf32_Rel));
        try reader.seekTo(rel_shdr.sh_offset);
        for (0..rels_len) |_| {
            const rel_hdr = try reader.interface.takeStruct(elf.Elf32_Rel, .little);

            // Don't really know if we could have any other relocations, AAELF is not *very* specific.
            // It seems we will always get R_ARM_RELATIVE ones.
            if (rel_hdr.r_type() != R_ARM_RELATIVE or rel_hdr.r_sym() != 0) return error.InvalidRelocations;

            try relocations.append(gpa, rel_hdr.r_offset);
        }

        break :relocs relocations;
    } else .empty;

    return .{
        .entrypoint = hdr.e_entry,
        .segments = map,
        .relocations = relocations,
    };
}

const std = @import("std");
const elf = std.elf;
