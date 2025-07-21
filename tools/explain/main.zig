const Subcommand = enum { result };
const Self = @This();

pub const description = "explain an horizon result code";

pub const Arguments = struct {
    pub const description = Self.description;


    command: union(Subcommand) {
        pub const descriptions = .{
            .result = "decompose a result into its components (level, module, summary and description)",
        };

        result: struct {
            positional: struct {
                pub const descriptions = .{
                    .result = "the result code to explain",
                };

                result: []const u8,
            },
        }
    },
};

pub fn main(arena: std.mem.Allocator, arguments: Arguments) !u8 {
    _ = arena;
    return switch (arguments.command) {
        .result => |r| {
            const result_str = r.positional.result;
            const result_int = std.fmt.parseUnsigned(u32, result_str, 0) catch |err| switch (err) {
                error.Overflow => {
                    std.debug.print("integer '{s}' does not fit into an u32\n", .{ result_str });
                    return 1;
                },
                error.InvalidCharacter => {
                    std.debug.print("integer '{s}' has an invalid character\n", .{ result_str });
                    return 1;
                },
            };

            const result_code: ResultCode = @bitCast(result_int);
            
            const stdout = std.io.getStdOut();
            const stdout_writer = stdout.writer();
            var stdout_buffered = std.io.bufferedWriter(stdout_writer);

            try stdout_writer.print(
                \\.{{
                \\    .level = .{s}, // ({})
                \\    .module = .{s}, // ({})
                \\    .summary = .{s}, // ({})
                \\    .description = .{s}, // ({})
                \\}}
                \\
            , .{
                std.enums.tagName(ResultLevel, result_code.level) orelse "<unknown>",
                @intFromEnum(result_code.level),
                std.enums.tagName(ResultModule, result_code.module) orelse "<unknown>",
                @intFromEnum(result_code.module),
                std.enums.tagName(ResultSummary, result_code.summary) orelse "<unknown>",
                @intFromEnum(result_code.summary),
                std.enums.tagName(ResultDescription, result_code.description) orelse "<unknown>",
                @intFromEnum(result_code.description),
            });
            try stdout_buffered.flush();
            return 0;
        }
    };
}

const std = @import("std");
const zitrus_tooling = @import("zitrus-tooling");
const result = zitrus_tooling.horizon.result;
const ResultCode = result.ResultCode;
const ResultLevel = result.ResultLevel;
const ResultModule = result.ResultModule;
const ResultSummary = result.ResultSummary;
const ResultDescription = result.ResultDescription;
