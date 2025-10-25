//! Extract code from different executable files for conversion purposes.
//!
//! Processes `Segment`s and extracts information from them.
//! Only one `Segment` type per executable is supported.
//!
//! Optionally and if the executable supports it,
//! extracts all relocation information.

pub const Segment = struct {
    pub const Kind = enum {
        unknown,
        any,
        text,
        rodata,
        data,

        pub fn fromElfFlags(flags: u32) Kind {
            return switch (flags) {
                elf.PF_R | elf.PF_W | elf.PF_X => .any,
                elf.PF_R | elf.PF_X => .text,
                elf.PF_R => .rodata,
                elf.PF_R | elf.PF_W => .data,
                else => .unknown,
            };
        }
    };

    kind: Kind,
    virtual_address: u32,
    physical_address: u32,
    file_offset: u32,
    file_size: u32,
    memory_size: u32,

    pub fn lessThan(_: void, a: Segment, b: Segment) bool {
        return a.physical_address < b.physical_address and a.virtual_address < b.virtual_address;
    }
};

/// Represents an executable with a fixed structure.
pub const Info = struct {
    entrypoint: u32,
    /// Sorted by physical address then virtual address.
    segments: []const Segment,
    /// Sorted by virtual address.
    relocations: []const u32,

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

        var segments: std.ArrayList(Segment) = try .initCapacity(gpa, hdr.e_phnum);
        errdefer segments.deinit(gpa);

        try reader.seekTo(hdr.e_phoff);
        for (0..hdr.e_phnum) |_| {
            const phdr = try reader.interface.takeStruct(elf.Elf32_Phdr, .little);

            if (phdr.p_type == elf.PT_INTERP) return error.DynamicallyLinked;
            if (phdr.p_type != elf.PT_LOAD or phdr.p_memsz == 0) continue;

            const kind: Segment.Kind = .fromElfFlags(phdr.p_flags);

            try segments.append(gpa, .{
                .kind = kind,
                .physical_address = phdr.p_paddr,
                .virtual_address = phdr.p_vaddr,
                .file_offset = phdr.p_offset,
                .file_size = phdr.p_filesz,
                .memory_size = phdr.p_memsz,
            });
        }

        std.mem.sort(Segment, segments.items, {}, Segment.lessThan);

        try reader.seekTo(hdr.e_shoff);
        const maybe_rel_shdr: ?elf.Elf32_Shdr = rel_hdr: for (0..hdr.e_shnum) |_| {
            const shdr = try reader.interface.takeStruct(elf.Elf32_Shdr, .little);

            if (shdr.sh_type == elf.SHT_REL and (shdr.sh_flags & elf.SHF_ALLOC) != 0) break :rel_hdr shdr;
        } else null;

        var relocations: std.ArrayList(u32) = if (maybe_rel_shdr) |rel_shdr| relocs: {
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

            std.mem.sort(u32, relocations.items, {}, std.sort.asc(u32));
            break :relocs relocations;
        } else .empty;

        return .{
            .entrypoint = hdr.e_entry,
            .segments = try segments.toOwnedSlice(gpa),
            .relocations = try relocations.toOwnedSlice(gpa),
        };
    }

    /// Streams the segments sequentially to the writer aligning to `alignment`.
    pub fn alignedStream(info: Info, writer: *std.Io.Writer, reader: *std.fs.File.Reader, segment_alignment: std.mem.Alignment) !void {
        for (info.segments) |seg| {
            try reader.seekTo(seg.file_offset);
            try reader.interface.streamExact(writer, seg.file_size);
            try writer.splatByteAll(0x00, std.mem.alignForward(u32, seg.file_size, @intCast(segment_alignment.toByteUnits())) - seg.file_size);
        }
    }

    pub fn deinit(info: *Info, gpa: std.mem.Allocator) void {
        gpa.free(info.segments);
        gpa.free(info.relocations);
    }

    /// Returns the first non-sequential `Segment` index (according to physical address) or null.
    pub fn findNonSequentialPhysicalSegment(info: Info, alignment: std.mem.Alignment) ?usize {
        if (info.segments.len == 0) return null;

        var last = info.segments[0];

        for (info.segments[1..], 1..) |segment, i| {
            const next_address = std.mem.alignForward(usize, last.physical_address + last.memory_size, alignment.toByteUnits());

            if (next_address != segment.physical_address) return i;

            last = segment;
        }

        return null;
    }

    pub fn findSegmentWithBss(info: Info) ?usize {
        for (info.segments, 0..) |segment, i| {
            if (segment.memory_size != segment.file_size) return i;
        }

        return null;
    }
};

const std = @import("std");
const elf = std.elf;
