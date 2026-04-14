// NOTE: We could support debug info by embedding the dwarf data into the 3dsx and/or
// inside the RomFS: romfs:/dbg.dwp (split dwarf debug info is mandatory here!)
// We could also store the ELF in the RomFS instead, but we literally double the executable size.

pub const init: SelfInfo = .{};

pub fn deinit(si: *SelfInfo, io: Io) void {
    _ = si;
    _ = io;
}

pub fn getSymbols(si: *SelfInfo, io: Io, symbol_allocator: Allocator, text_arena: Allocator, address: usize, include_inline_callers: bool, symbols: *std.ArrayList(Symbol)) Error!void {
    _ = si;
    _ = io;
    _ = symbol_allocator;
    _ = text_arena;
    _ = address;
    _ = include_inline_callers;
    _ = symbols;
    return error.MissingDebugInfo;
}

pub fn getModuleName(si: *SelfInfo, io: Io, address: usize) Error![]const u8 {
    _ = si;
    _ = io;
    _ = address;
    return error.MissingDebugInfo;
}

pub fn getModuleSlide(si: *SelfInfo, io: Io, address: usize) Error!usize {
    _ = si;
    _ = io;
    _ = address;
    return error.MissingDebugInfo;
}

pub const can_unwind = false;

const Error = std.debug.SelfInfoError;
const Symbol = std.debug.Symbol;
const Allocator = std.mem.Allocator;
const SelfInfo = @This();

const std = @import("std");
const Io = std.Io;
