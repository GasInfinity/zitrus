// The defacto format for Nintendo 3DS Homebrew executables.
// For more info: https://3dbrew.org/wiki/3DSX_Format

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
    words_to_skip: u32,
    words_to_patch: u32,
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

const ElfSegmentData = struct {
    // code address is implicitly the base address also
    code_address: u32,
    rodata_address: u32,
    data_address: u32,
    top_address: u32,

    code_segment_offset: u32,
    data_segment_offset: u32,
    rodata_segment_offset: u32,

    code_segment_size: u32,
    rodata_segment_size: u32,
    data_segment_size: u32,
    bss_size: u32,
};

const ElfSymbolData = struct {
    address: u32,
    len: u32,
    values: u32,
};

// TODO: Add support for embedding SMDH and RomFS data !!!
pub fn processElf(out_3dsx: anytype, in_elf: []const u8) !void {
    const elf_header: elf.Elf32_Ehdr = std.mem.bytesToValue(elf.Elf32_Ehdr, in_elf[0..@sizeOf(elf.Elf32_Ehdr)]);

    if (!std.mem.eql(u8, elf_header.e_ident[0..4], elf.MAGIC)) return error.InvalidElfMagic;
    if (elf_header.e_ident[elf.EI_VERSION] != 1) return error.InvalidElfVersion;
    if (elf_header.e_ident[elf.EI_CLASS] != 1 or elf_header.e_machine != .ARM) return error.InvalidMachine;
    if (elf_header.e_type != .EXEC) return error.NotExecutable;

    const segments: []const elf.Elf32_Phdr = @alignCast(std.mem.bytesAsSlice(elf.Elf32_Phdr, in_elf[elf_header.e_phoff..][0..(elf_header.e_phnum * @sizeOf(elf.Elf32_Phdr))]));
    const segment_data = try processSegments(segments);

    if (elf_header.e_entry != segment_data.code_address) return error.InvalidEntryAddress;

    // TODO: process relocations
    try out_3dsx.writeStruct(Header{
        .header_size = @sizeOf(Header),
        .relocation_header_size = @sizeOf(RelocationHeader),
        .version = 0x0,
        .flags = 0x0,
        .code_segment_size = segment_data.code_segment_size,
        .rodata_segment_size = segment_data.rodata_segment_size,
        .data_segment_size = segment_data.data_segment_size,
        .bss_segment_size = segment_data.bss_size,
    });

    // TODO: write relocations
    // code
    try out_3dsx.writeStruct(std.mem.zeroes(RelocationHeader));
    // rodata
    try out_3dsx.writeStruct(std.mem.zeroes(RelocationHeader));
    // data
    try out_3dsx.writeStruct(std.mem.zeroes(RelocationHeader));

    try out_3dsx.writeAll(in_elf[segment_data.code_segment_offset..][0..segment_data.code_segment_size]);

    if (segment_data.rodata_segment_offset != 0) {
        try out_3dsx.writeAll(in_elf[segment_data.rodata_segment_offset..][0..segment_data.rodata_segment_size]);
    }

    if (segment_data.data_segment_offset != 0) {
        try out_3dsx.writeAll(in_elf[segment_data.data_segment_offset..][0..(segment_data.data_segment_size - segment_data.bss_size)]);
    }
}

fn processSegments(segments: []const elf.Elf32_Phdr) ElfConversionError!ElfSegmentData {
    const ElfSegmentConversionState = union(enum) {
        waiting_code_segment,
        waiting_rodata_or_data_segment,
        waiting_data_segment,
        finished,
    };

    var segment_state: ElfSegmentConversionState = .waiting_code_segment;
    var segment_data: ElfSegmentData = std.mem.zeroes(ElfSegmentData);

    for (segments) |segment| {
        if (segment.p_type != elf.PT_LOAD or segment.p_memsz == 0) {
            continue;
        }

        if (!std.mem.isAligned(segment.p_memsz, 4)) {
            return error.UnalignedSegmentMemory;
        }

        if (segment.p_memsz != segment.p_filesz and segment.p_flags != (elf.PF_R | elf.PF_W)) {
            return error.NonDataSegmentHasBss;
        }

        st: switch (segment_state) {
            .waiting_code_segment => {
                if (segment.p_flags != (elf.PF_R | elf.PF_X)) {
                    return error.CodeSegmentMustBeFirst;
                }

                segment_data.code_address = segment.p_vaddr;
                segment_data.code_segment_offset = segment.p_offset;
                segment_data.code_segment_size = segment.p_memsz;
                segment_state = .waiting_rodata_or_data_segment;
            },
            .waiting_rodata_or_data_segment => {
                if (segment.p_flags == (elf.PF_R | elf.PF_W)) {
                    continue :st .waiting_data_segment;
                }

                if (segment.p_flags != elf.PF_R) {
                    return error.RodataSegmentMustBeSecond;
                }

                if (segment.p_vaddr != segment_data.top_address) {
                    return error.NonContiguousSegment;
                }

                segment_data.rodata_address = segment.p_vaddr;
                segment_data.rodata_segment_offset = segment.p_offset;
                segment_data.rodata_segment_size = segment.p_memsz;
                segment_state = .waiting_data_segment;
            },
            .waiting_data_segment => {
                if (segment.p_flags != (elf.PF_R | elf.PF_W)) {
                    return error.DataSegmentMustBeLast;
                }

                if (segment.p_vaddr != segment_data.top_address) {
                    return error.NonContiguousSegment;
                }

                segment_data.data_address = segment.p_vaddr;
                segment_data.data_segment_offset = segment.p_offset;
                segment_data.data_segment_size = segment.p_memsz;
                segment_data.bss_size = segment.p_memsz - segment.p_filesz;
                segment_state = .finished;
            },
            .finished => return error.InvalidSegment,
        }

        segment_data.top_address = std.mem.alignForward(u32, segment.p_vaddr + segment.p_memsz, 4096);
    }

    return segment_data;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const elf = std.elf;
