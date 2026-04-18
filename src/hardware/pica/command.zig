//! Type-safe PICA200 `pica.Graphics` command wrappers and types.
//!
//! Address and Size of command queues/buffers/lists must be aligned to 16 bytes
//! Commands are aligned to 8 bytes

pub const Header = packed struct(u32) {
    pub const Mode = enum(u1) { consecutive, incremental };

    id: Id,
    mask: u4,
    extra: u8,
    _unused0: u3 = 0,
    mode: Mode,
};

pub const Id = enum(u16) {
    _,

    pub fn fromRegister(comptime base: *volatile pica.Graphics, register: *volatile anyopaque) Id {
        std.debug.assert(@intFromPtr(register) >= @intFromPtr(base) and @intFromPtr(register) < (@intFromPtr(base) + @sizeOf(pica.Graphics))); // invalid internal register, pointer is not within the valid range

        const offset = @intFromPtr(register) - @intFromPtr(base);

        std.debug.assert((offset % @alignOf(u32)) == 0); // invalid internal register, it must be aligned to 4 bytes

        return @enumFromInt(@divExact(offset, @alignOf(u32)));
    }
};

/// WARNING: using this will bloat your binary!
pub const Dump = struct {
    pub const Iterator = struct {
        words: []const u32,
        current: u32,

        pub fn init(words: []const u32) Iterator {
            return .{ .words = words, .current = 0 };
        }

        pub fn next(it: *Iterator) ?Dump {
            if (it.current + 1 >= it.words.len) return null;
            const hdr: Header = @bitCast(it.words[it.current + 1]);
            const full_len = 2 + @as(u32, hdr.extra);
            defer it.current += std.mem.alignForward(u32, full_len, 2);

            return .{ .words = it.words[it.current..][0..@min(full_len, it.words.len - it.current)] };
        }
    };

    pub const Single = struct {
        // XXX: This is quite bad, a rewrite would be good
        pub const Info = struct {
            /// Fully qualified name
            name: []const u8,
            type: type,

            pub fn findName(id: Id) []const u8 {
                return switch (@intFromEnum(id)) {
                    (@sizeOf(pica.Graphics) / @sizeOf(u32))...0xFFFF => "<not found>",
                    inline else => |word_offset| find(word_offset * @sizeOf(u32)).name,
                };
            }

            pub fn find(comptime offset: u32) Info {
                @setEvalBranchQuota(200000);

                var current = Search.find(pica.Graphics, offset);
                var current_offset = offset - @offsetOf(pica.Graphics, current.name);
                var fully_qualified_name = current.name;
                while (@sizeOf(current.type) > @sizeOf(u32)) switch (@typeInfo(current.type)) {
                    .@"struct" => |st| switch (st.layout) {
                        .auto => unreachable,
                        .@"packed" => unreachable, // Hitting this means you have an invalid packed struct in there.
                        .@"extern" => {
                            const next = Search.find(current.type, current_offset);

                            current_offset -= @offsetOf(current.type, next.name);
                            current = next;
                            
                            fully_qualified_name = fully_qualified_name ++ "." ++ next.name;
                        },
                    },
                    .array => |array| switch(std.math.order(@sizeOf(array.child), @sizeOf(u32))) {
                        .lt => current.type = [@divExact(@sizeOf(u32), @sizeOf(array.child))]array.child,
                        .eq, .gt => {
                            fully_qualified_name = fully_qualified_name ++ std.fmt.comptimePrint("[{d}]", .{current_offset / @sizeOf(array.child)});
                            current_offset %= @sizeOf(array.child);
                            current.type = array.child;
                        },
                    },
                    else => @compileError("TODO"),
                };

                return .{ .name = fully_qualified_name, .type = current.type };
            }

            const Search = struct {
                parent: type,
                offset: u32,

                pub fn find(comptime T: type, comptime offset: u32) Info {
                    const fields = @typeInfo(T).@"struct".fields;
                    const ctx: Search = .{ .parent = T, .offset = offset };
                    const index = std.sort.binarySearch(std.builtin.Type.StructField, fields, ctx, Search.compare) orelse unreachable;
                    return .{ .name = fields[index].name, .type = fields[index].type };
                }

                pub fn compare(ctx: Search, field: std.builtin.Type.StructField) std.math.Order {
                    const field_offset = @offsetOf(ctx.parent, field.name);
                    if (ctx.offset < field_offset) return .lt;
                    if (ctx.offset >= field_offset + @sizeOf(field.type)) return .gt;
                    return .eq;
                }
            };
        };

        mode: Header.Mode,
        id: Id,
        raw: u32,

        pub fn format(single: Single, w: *std.Io.Writer) std.Io.Writer.Error!void {
            switch (@intFromEnum(single.id)) {
                (@sizeOf(pica.Graphics) / @sizeOf(u32))...0xFFFF => try w.print("{X:0>8}", .{single.raw}),
                inline else => |word_offset| {
                    const info: Info = .find(word_offset * @sizeOf(u32)); 

                    switch (single.mode) {
                        .incremental => {
                            try w.print("{s} ({X:0>3}) -> ", .{info.name, single.id});
                            try printValue(info.type, single.raw, w);
                        },
                        .consecutive => try printValue(info.type, single.raw, w),
                    }
                },
            }
        }

        pub fn printValue(comptime T: type, raw: u32, w: *std.Io.Writer) std.Io.Writer.Error!void {
            const typed: T = switch (@typeInfo(T)) {
                .@"enum" => @enumFromInt(raw),
                else => @bitCast(raw),
            };

            try w.print(if (std.meta.hasFn(T, "format")) "{f}" else if (T == u32) "{X:0>8}" else "{any}", .{typed});
        }
    };

    words: []const u32,

    pub fn format(dump: Dump, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const hdr: Header = @bitCast(dump.words[1]);

        switch (hdr.mode) {
            .incremental => try w.print("{t} ({b:0>4})", .{hdr.mode, hdr.mask}),
            .consecutive => try w.print("{t}: {s} ({X:0>3}, {b:0>4})", .{hdr.mode, Single.Info.findName(hdr.id), hdr.id, hdr.mask}),
        }

        if (hdr.extra > 0) try w.writeByte('\n');

        var single: Single = .{
            .mode = hdr.mode,
            .id = hdr.id,
            .raw = dump.words[0],
        };


        var i: u32 = 0;
        while (true) {
            try w.print("... {f}", .{single});

            if (i >= hdr.extra) break;
            try w.writeByte('\n');
            single = .{
                .mode = hdr.mode,
                .raw = dump.words[2 + i],
                .id = switch (hdr.mode) {
                    .consecutive => single.id,
                    .incremental => @enumFromInt(@intFromEnum(single.id) + 1),
                },
            };
            i += 1;
        }
    }
};

pub const Queue = struct {
    pub const empty: Queue = .{ .buffer = .empty, .end = 0 };

    buffer: []align(16) u32,
    end: u32,

    pub fn initBuffer(buffer: []align(16) u32) Queue {
        return .{
            .buffer = buffer,
            .end = 0,
        };
    }

    pub fn slice(queue: Queue) []align(16) u32 {
        return queue.buffer[0..queue.end];
    }

    pub fn unusedCapacitySlice(queue: Queue) []align(8) u32 {
        return @alignCast(queue.buffer[queue.end..]);
    }

    pub fn reset(queue: *Queue) void {
        queue.end = 0;
    }

    pub inline fn add(queue: *Queue, comptime base: *volatile pica.Graphics, register: anytype, value: std.meta.Child(@TypeOf(register))) void {
        return queue.addMasked(base, register, value, 0xF);
    }

    pub fn addMasked(queue: *Queue, comptime base: *volatile pica.Graphics, register: anytype, value: std.meta.Child(@TypeOf(register)), mask: u4) void {
        comptime std.debug.assert(@typeInfo(@TypeOf(register)) == .pointer);

        const Child = std.meta.Child(@TypeOf(register));
        const child_info = @typeInfo(Child);

        const id: Id = .fromRegister(base, register);

        switch (comptime std.math.order(@bitSizeOf(Child), @bitSizeOf(u32))) {
            .eq => queue.addMaskedBuffer(id, &.{switch (child_info) {
                .@"enum" => @intFromEnum(value),
                else => @bitCast(value),
            }}, mask, .consecutive),
            .gt => {
                const as_u32_array = switch (child_info) {
                    .array => |a| if (@bitSizeOf(a.child) != @bitSizeOf(u32))
                        @compileError("only arrays of 32-bit types are supported for incremental writes")
                    else
                        @as([a.len]u32, @bitCast(value)),
                    .@"struct" => |s| if (s.layout == .auto or (@bitSizeOf(Child) % @bitSizeOf(u32)) != 0)
                        @compileError("only non-auto structs with a bitSize multiple of 32 are supported")
                    else
                        @as([@divExact(@bitSizeOf(Child), @bitSizeOf(u32))]u32, @bitCast(value)),
                    else => @compileError("unsupported type for incremental write"),
                };

                queue.addMaskedBuffer(id, &as_u32_array, mask, .incremental);
            },
            .lt => @compileError("commands only support writing full 32-bit values (which you can mask!)"),
        }
    }

    fn IncrementalWritesTuple(comptime base: *volatile pica.Graphics, comptime registers: anytype) type {
        const RegistersType = @TypeOf(registers);

        comptime std.debug.assert(@typeInfo(RegistersType) == .@"struct");
        const st_ty = @typeInfo(RegistersType).@"struct";

        comptime std.debug.assert(st_ty.is_tuple);

        var needed_field_types: [st_ty.fields.len]type = undefined;

        @setEvalBranchQuota(st_ty.fields.len * 2000);
        for (st_ty.fields, 0..) |field, i| {
            std.debug.assert(@typeInfo(field.type) == .pointer);

            const f_ty = @typeInfo(field.type).pointer;
            const current = registers[i];
            const current_id: Id = .fromRegister(base, current);

            if (@bitSizeOf(f_ty.child) != @bitSizeOf(u32)) @compileLog("only values with a @bitSizeOf(u32) are supported.");

            if (i > 0) {
                const last_id: Id = .fromRegister(base, registers[i - 1]);

                comptime std.debug.assert(std.math.order(@intFromEnum(current_id), @intFromEnum(last_id)) == .gt);
                comptime std.debug.assert((@intFromEnum(current_id) - @intFromEnum(last_id)) == 1);
            }

            needed_field_types[i] = f_ty.child;
        }

        return @Tuple(&needed_field_types);
    }

    pub inline fn addIncremental(queue: *Queue, comptime base: *volatile pica.Graphics, comptime registers: anytype, values: IncrementalWritesTuple(base, registers)) void {
        return queue.addIncrementalMasked(base, registers, values, 0b1111);
    }

    pub fn addIncrementalMasked(queue: *Queue, comptime base: *volatile pica.Graphics, comptime registers: anytype, values: IncrementalWritesTuple(base, registers), mask: u4) void {
        if (registers.len == 0) return;

        comptime std.debug.assert(values.len <= 256);
        const first_id: Id = .fromRegister(base, registers[0]);

        var u32_values: [values.len]u32 = undefined;
        inline for (&u32_values, 0..) |*v, i| v.* = switch (@typeInfo(@TypeOf(values[i]))) {
            .@"enum" => @intFromEnum(values[i]),
            else => @bitCast(values[i]),
        };

        return queue.addMaskedBuffer(first_id, &u32_values, mask, .incremental);
    }

    pub inline fn addConsecutive(queue: *Queue, comptime base: *volatile pica.Graphics, register: anytype, values: []const std.meta.Child(@TypeOf(register))) void {
        return queue.addConsecutiveMasked(base, register, values, 0b1111);
    }

    pub fn addConsecutiveMasked(queue: *Queue, comptime base: *volatile pica.Graphics, register: anytype, values: []const std.meta.Child(@TypeOf(register)), mask: u4) void {
        comptime std.debug.assert(@typeInfo(@TypeOf(register)) == .pointer);

        const Child = std.meta.Child(@TypeOf(register));
        const id: Id = .fromRegister(base, register);

        comptime std.debug.assert(@bitSizeOf(Child) == @bitSizeOf(u32));

        return queue.addMaskedBuffer(id, @ptrCast(values), mask, .consecutive);
    }

    pub fn addMaskedBuffer(queue: *Queue, id: Id, values: []const u32, mask: u4, mode: Header.Mode) void {
        if (values.len == 0) return;

        var current_id: Id = id;
        var current: usize = 0;
        var remaining: usize = values.len;

        while (remaining > 0) {
            const len = @min(remaining, 256);
            defer {
                current += len;
                remaining -= len;
            }

            const remaining_slice = values[current..][0..len];

            queue.buffer[queue.end] = remaining_slice[0];
            queue.buffer[queue.end + 1] = @bitCast(Header{
                .id = id,
                .mask = mask,
                .extra = @intCast(len - 1),
                .mode = mode,
            });
            queue.end += 2;

            @memcpy(queue.buffer[queue.end..][0..(len - 1)], remaining_slice[1..len]);
            queue.end += std.mem.alignForward(usize, len - 1, 2); // commands must be aligned to 8 bytes
            if (mode == .incremental) current_id = @enumFromInt(@intFromEnum(current_id) + len);
        }
    }

    pub fn chain(queue: *Queue, address: zitrus.hardware.AlignedPhysicalAddress(.@"16", .@"8")) *zitrus.hardware.LsbRegister(u22) {
        const p3d = &zitrus.memory.arm11.pica.p3d;

        const size = &queue.buffer[queue.end];
        queue.add(p3d, &p3d.primitive_engine.command_buffer.size[0], .init(0));
        queue.add(p3d, &p3d.primitive_engine.command_buffer.address[0], address);
        queue.add(p3d, &p3d.primitive_engine.command_buffer.jump[0], .init(.trigger));

        if (!std.mem.isAligned(queue.end, 4)) {
            queue.add(p3d, &p3d.primitive_engine.command_buffer.jump[0], .init(.trigger));
        }

        return @ptrCast(size);
    }

    pub fn finalize(queue: *Queue) void {
        const p3d = &zitrus.memory.arm11.pica.p3d;

        queue.add(p3d, &p3d.irq.req[0..4].*, @bitCast(@as(u32, 0x12345678)));

        if (!std.mem.isAligned(queue.end, 4)) {
            queue.add(p3d, &p3d.irq.req[0..4].*, @bitCast(@as(u32, 0x12345678)));
        }
    }
};

/// Represents a growable command stream (multiple chained command queues)
pub const stream = struct {
    pub const StreamResetMode = enum { free_all, retain_largest };
    pub const Segment = struct {
        queue: Queue,
        node: std.SinglyLinkedList.Node,

        comptime {
            std.debug.assert(@sizeOf(Segment) == 16);
        }

        pub fn data(segment: *Segment) []align(16) u32 {
            return @as([*]align(16) u32, @ptrCast(@alignCast(segment)))[0 .. @divExact(@sizeOf(Segment), @sizeOf(u32)) + segment.queue.buffer.len];
        }
    };

    /// Context must have a field called `use_jumps` which toggles whether the stream
    /// is a single command queue or multiple chained ones (when growing it)
    ///
    /// If `use_jumps` is not comptime-known or is `true`, it must also implement
    /// `fn virtualToPhysical(ctx, virtual: *align(4096) const anyopaque) zitrus.hardware.PhysicalAddress`.
    pub fn Custom(comptime Context: type) type {
        return struct {
            pub const empty: Stream = .{ .list = .{}, .last_chain_size = null, .initial_chunk = &.{}, .start = 0 };

            list: std.SinglyLinkedList,
            last_chain_size: ?*zitrus.hardware.LsbRegister(u22),
            initial_chunk: []align(16) const u32,
            /// This is intended to be modified directly, must be aligned to 4 words (16 bytes)
            ///
            /// Changes when finalizing or chaining queues (e.g when growing)
            start: u32,

            pub fn deinit(strm: *Stream, gpa: std.mem.Allocator) void {
                strm.reset(gpa, .free_all);
                strm.* = undefined;
            }

            pub fn first(strm: *Stream) ?*Queue {
                const head = strm.list.first orelse return null;
                const segment: *Segment = @fieldParentPtr("node", head);
                return &segment.queue;
            }

            /// Grows the stream exponentially, i.e 4096->8192->16384; starting from `min_len`
            pub fn grow(
                strm: *Stream,
                gpa: std.mem.Allocator,
                /// Length of the first queue *in `u32`*s
                min_len: u32,
                ctx: Context,
            ) !void {
                std.debug.assert(min_len >= @sizeOf(Segment)); // You're crazy, please bump the len A LOT.
                std.debug.assert(std.mem.isAligned(strm.start, 4));

                const segment = if (strm.list.first) |node| blk: {
                    const first_segment: *Segment = @alignCast(@fieldParentPtr("node", node));
                    const first_que: *Queue = &first_segment.queue;
                    const first_data = first_segment.data();
                    const next_len = first_data.len << 1;

                    if (!ctx.use_jumps) {
                        std.debug.assert(first_segment.node.next == null);

                        const new_len = first_data.len + next_len;
                        const new = if (gpa.remap(first_data, new_len)) |remapped| remapped else remapped: {
                            const new = try gpa.alignedAlloc(u32, .@"16", new_len);
                            defer gpa.free(first_data);

                            const copying = first_data[0 .. @divExact(@sizeOf(Segment), @sizeOf(u32)) + first_segment.queue.end];
                            @memcpy(new[0..copying.len], copying);
                            break :remapped new;
                        };

                        const new_segment: *Segment = @ptrCast(new);
                        // NOTE: we copied all commands above
                        new_segment.queue.buffer = new[@divExact(@sizeOf(Segment), @sizeOf(u32))..];
                        strm.list.first = &new_segment.node;
                        return;
                    }

                    const new_segment = try allocSegment(gpa, next_len);
                    const had_last_chain = strm.last_chain_size != null;

                    if (strm.last_chain_size) |last_size| {
                        const len = (first_que.end - strm.start);
                        last_size.* = .init(@intCast((len * @sizeOf(u32)) >> 3));
                    }

                    strm.last_chain_size = first_que.chain(.fromPhysical(ctx.virtualToPhysical(new_segment.queue.buffer.ptr)));

                    if (!had_last_chain) {
                        strm.initial_chunk = @alignCast(first_que.buffer[strm.start..first_que.end]);
                    }

                    strm.start = 0;
                    break :blk new_segment;
                } else try allocSegment(gpa, min_len);

                strm.list.prepend(&segment.node);
            }

            /// Finalizes and returns the initial chunk of the stream or null if none.
            pub fn finalize(strm: *Stream) ?[]align(16) const u32 {
                std.debug.assert(std.mem.isAligned(strm.start, 4));

                const que = strm.first() orelse return null;

                // Nothing to finalize
                if (strm.start == que.end and strm.last_chain_size == null) return null;
                que.finalize();

                const initial_chunk: []align(16) const u32 = if (strm.last_chain_size) |last_size| blk: {
                    last_size.* = .init(@intCast(((que.end - strm.start) * @sizeOf(u32)) >> 3));
                    break :blk strm.initial_chunk;
                } else @alignCast(que.buffer[strm.start..que.end]);

                strm.last_chain_size = null;
                strm.start = que.end;
                return initial_chunk;
            }

            pub fn reset(strm: *Stream, gpa: std.mem.Allocator, mode: StreamResetMode) void {
                const first_node = strm.list.first orelse return;
                strm.last_chain_size = null;
                strm.initial_chunk = &.{};
                strm.start = 0;

                var freeing = switch (mode) {
                    .free_all => blk: {
                        strm.list.first = null;
                        break :blk first_node;
                    },
                    .retain_largest => blk: {
                        first_node.next = null;

                        const first_segment: *Segment = @fieldParentPtr("node", first_node);
                        first_segment.queue.end = 0;
                        break :blk first_node.next;
                    },
                };

                while (freeing) |node| {
                    freeing = node.next;

                    const segment: *Segment = @alignCast(@fieldParentPtr("node", node));
                    const segment_data = segment.data();
                    gpa.free(segment_data);
                }
            }

            fn allocSegment(gpa: std.mem.Allocator, len: u32) !*Segment {
                const data = try gpa.alignedAlloc(u32, .@"16", len);
                const segment: *Segment = @ptrCast(data);

                segment.* = .{
                    .queue = .{
                        .buffer = data[@divExact(@sizeOf(Segment), @sizeOf(u32))..],
                        .end = 0,
                    },
                    .node = .{},
                };

                return segment;
            }

            const Stream = @This();
        };
    }
};

const std = @import("std");

const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;
