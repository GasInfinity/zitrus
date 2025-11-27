pub const description =
    \\Generate Markdown documentation from the zitrus SDK
;

@"--": struct {
    pub const descriptions = .{ .output = "Output directory" };

    output: []const u8,
},

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa_state.deinit() == .ok);

    const gpa = gpa_state.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const arguments = zdap.Parser.parse(@This(), "gen-md-docs", args, .{});
    _ = arguments;

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writerStreaming(&out_buf);
    const output = &stdout_writer.interface;

    inline for (@typeInfo(zitrus.horizon.services).@"struct".decls) |service_decl| {
        const zitrus_name = service_decl.name;
        const ServiceType = @field(zitrus.horizon.services, zitrus_name);
        const spans_multiple_services = @hasDecl(ServiceType, "Service");

        try output.print("# {s}\n\n", .{zitrus_name});

        if(spans_multiple_services) {
            const ServicesEnum = @field(ServiceType, "Service");
            const services = std.enums.values(ServicesEnum);

            try output.print("Service(s): ", .{});

            for (services, 0..) |service, i| {
                try output.print("`{s}`", .{service.name()}); 

                if(i + 1 < services.len) try output.writeAll(", ");
            }
            try output.writeByte('\n');
        } else try output.print("Service: `{s}`\n", .{@field(ServiceType, "service")});
        try output.writeAll("\n---\n\n");

        if(!@hasDecl(ServiceType, "command") or !@hasDecl(ServiceType.command, "Id")) {
            log.warn("Service `{}` is not conformant as it doesn't have a `command` decl or an `Id` enum inside", .{});
            continue;
        }

        const id_commands = @typeInfo(ServiceType.command).@"struct".decls;

        // Will always be 1 as `Id` is there.
        if(id_commands.len > 1) {
            inline for (id_commands) |command| {
                if(comptime std.mem.eql(u8, command.name, "Id")) continue; // The only decl allowed there appart from the commands themselves
                
                const Command = @field(ServiceType.command, command.name);
                const name = command.name;
                const id = Command.id;

                try output.print("* `{s}`: (0x{X:0>4})\n", .{name, id});
            }

            try output.writeByte('\n');
        }
    }

    try output.flush();
}

const log = std.log.scoped(.@"gen-md");

const std = @import("std");
const zdap = @import("zdap");
const zitrus = @import("zitrus");
