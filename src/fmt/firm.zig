//! 3DS Firmware
//!
//! Firm sections are expected to be aligned to `512` bytes.
//! Not documented explicitly, thanks folf20 from the Godmode9 discord server.
//!
//! Contains both ARM9 and ARM11 `freestanding` binaries and possibly more data (e.g: sysmodules in official firmware)
//!
//! Based on the documentation found in 3dbrew: https://3dbrew.org/wiki/FIRM

pub const magic = "FIRM";

pub const Header = extern struct {
    magic: [4]u8 = magic.*,
    /// Higher values have higher priority.
    boot_priority: u32,
    arm11_entry: u32,
    arm9_entry: u32,
    _reserved0: [0x30]u8 = @splat(0),
    sections: [4]Section,
    /// RSA-2048 signature of the `Header` SHA-256 hash.
    signature: [0x100]u8,

    pub const CheckError = error{ NotFirm, UnalignedSectionOffset };
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotFirm;
        for (&hdr.sections) |section| {
            if (section.size == 0) continue;
            if (!std.mem.isAligned(section.offset, Section.min_alignment)) return error.UnalignedSectionOffset;
        }
    }
};

pub const Section = extern struct {
    pub const min_alignment = 512;
    pub const CopyMethod = enum(u32) { ndma, xdma, memcpy, _ };

    /// File offset of the section.
    offset: u32,
    address: u32,
    /// Size of the section in bytes.
    size: u32,
    copy_method: CopyMethod,
    /// SHA-256 hash of the section data.
    hash: [0x20]u8,

    pub fn check(section: Section, data: []const u8) bool {
        std.debug.assert(section.size == data.len);

        var data_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &data_hash, .{});
        return std.mem.eql(u8, &section.hash, &data_hash);
    }
};

const std = @import("std");
