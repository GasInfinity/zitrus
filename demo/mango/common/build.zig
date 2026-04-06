pub fn build(b: *std.Build) void {
    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    _ = b.addModule("common", .{
        .root_source_file = b.path("src/common.zig"),
        .imports = &.{
            .{ .name = "zitrus", .module = zitrus_mod },
        }
    });
}

const std = @import("std");
