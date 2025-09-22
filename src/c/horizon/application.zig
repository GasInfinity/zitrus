pub const Event = enum(i8) {
    none = -1,
    _,
};

pub export fn ztrHorAppSoftInit(gpa: c.ZigAllocator) ?*application.Software {
    const ally = gpa.allocator();
    const soft = ally.create(application.Software) catch {
        return null;
    };
    errdefer ally.destroy(soft);

    soft.* = application.Software.init(.default, ally) catch return null;
    return soft;
}

pub export fn ztrHorAppSoftDeinit(soft: *application.Software, gpa: c.ZigAllocator) void {
    const ally = gpa.allocator();

    soft.deinit(ally);
    ally.destroy(soft);
}

pub export fn ztrHorAppSoftPollEvent(soft: *application.Software) Event {
    return @enumFromInt(@intFromEnum(((soft.pollEvent() catch return .none) orelse return .none)));
}

const std = @import("std");
const zitrus = @import("zitrus");

const c = zitrus.c;
const horizon = zitrus.horizon;
const application = horizon.application;
