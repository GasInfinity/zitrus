// NOTE: We could support debug info by embedding the dwarf data into the 3dsx and/or
// inside the RomFS: romfs:/dbg.dwp (split dwarf debug info is mandatory here!)
// We could also store the ELF in the RomFS instead, but we literally double the executable size.

pub const init: SelfInfo = .{};

pub fn deinit(si: *SelfInfo, io: Io) void {
    _ = si;
    _ = io;
}

pub fn getSymbol(si: *SelfInfo, io: Io, address: usize) std.debug.SelfInfoError!std.debug.Symbol {
    _ = si;
    _ = io;
    _ = address;
    return error.MissingDebugInfo;
}

pub fn getModuleName(si: *SelfInfo, io: Io, address: usize) std.debug.SelfInfoError![]const u8 {
    _ = si;
    _ = io;
    _ = address;
    return error.MissingDebugInfo;
}

pub const can_unwind = false;

const SelfInfo = @This();

const std = @import("std");
const Io = std.Io;
