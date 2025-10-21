pub const description = "Explain things";

const Subcommand = enum { result };

pub const Result = struct {
    pub const description = "Decompose a result into its components (level, module, summary and description)";

    @"--": struct {
        pub const descriptions = .{
            .result = "The result code to explain",
        };

        result: []const u8,
    },
};

@"-": union(Subcommand) {
    result: Result,
},

pub fn main(args: Explain, arena: std.mem.Allocator) !u8 {
    _ = arena;
    return switch (args.@"-") {
        .result => |r| {
            const result_str = r.@"--".result;
            const result_int = std.fmt.parseUnsigned(u32, result_str, 0) catch |err| switch (err) {
                error.Overflow => {
                    std.debug.print("integer '{s}' does not fit into an u32\n", .{result_str});
                    return 1;
                },
                error.InvalidCharacter => {
                    std.debug.print("integer '{s}' has an invalid character\n", .{result_str});
                    return 1;
                },
            };

            const result_code: result.Code = @bitCast(result_int);

            var stdout_buffer: [256]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;

            try stdout.print(
                \\.{{
                \\    .level = .{s}, // ({})
                \\    .module = .{s}, // ({})
                \\    .summary = .{s}, // ({})
                \\    .description = .{s}, // ({})
                \\}}
                \\
            , .{
                std.enums.tagName(result.Level, result_code.level) orelse "<unknown>",
                @intFromEnum(result_code.level),
                std.enums.tagName(result.Module, result_code.module) orelse "<unknown>",
                @intFromEnum(result_code.module),
                std.enums.tagName(result.Summary, result_code.summary) orelse "<unknown>",
                @intFromEnum(result_code.summary),
                std.enums.tagName(result.Description, result_code.description) orelse "<unknown>",
                @intFromEnum(result_code.description),
            });
            try stdout.flush();
            return 0;
        },
    };
}

const Explain = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const result = zitrus.horizon.result;
