// NOTE: We could support debug info by embedding the dwarf data into the 3dsx and/or
// inside the RomFS (split dwarf debug info is mandatory here!)

pub const init: SelfInfo = .{};

pub fn deinit(si: *SelfInfo, gpa: std.mem.Allocator) void {
    _ = si;
    _ = gpa;
}

pub fn getSymbol(si: *SelfInfo, gpa: std.mem.Allocator, io: std.Io, address: usize) std.debug.SelfInfoError!std.debug.Symbol {
    _ = si;
    _ = gpa;
    _ = io;
    _ = address;
    return error.MissingDebugInfo;
}

pub fn getModuleName(si: *SelfInfo, gpa: std.mem.Allocator, address: usize) std.debug.SelfInfoError![]const u8 {
    _ = si;
    _ = gpa;
    _ = address;
    return error.MissingDebugInfo;
}

pub const can_unwind = false;

const SelfInfo = @This();

const std = @import("std");
