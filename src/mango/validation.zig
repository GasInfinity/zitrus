pub const Error = error{ValidationFailed};

pub const enabled = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseSmall, .ReleaseFast => false,
};

pub const image = struct {
    pub const must_be_correct =
        \\[Image] incorrect image: {d}x{d} ({t})
        \\| image dimensions must be multiples of 8, between 8 and 1024
    ;

    pub const sampled_must_be_correct =
        \\[Image] incorrect sampled image: {d}x{d} ({t})
        \\| sampled images must be optimally tiled and have powers of two dimensions
    ;

    pub const attachment_must_be_correct =
        \\[Image] incorrect attachment image: {d}x{d} ({t})
        \\| attachment images must be optimally tiled
    ;
};

pub const image_view = struct {
    pub const src_not_mutable_format =
        \\[ImageView] non-matching format
        \\| set the mutable_format flag in the source image to allow this
    ;

    pub const invalid_2d =
        \\[ImageView] invalid 2d view
        \\| 2d views must be backed strictly by 1 image layer
    ;

    pub const invalid_cube =
        \\[ImageView] invalid cube view
        \\| cube views must be backed strictly by 6 image layers
    ;
};

pub const graphics_state = struct {
    /// what must be set
    pub const must_be_set =
        \\[CommandBuffer] {[0]s} must be set
        \\| dynamic state is mandatory
    ;
};

pub const shader = struct {
    /// code type
    pub const unknown_code_type =
        \\[Shader] Code Type {}
        \\| unknown code type
    ;

    /// entrypoint name
    pub const entry_not_found =
        \\[Shader] Entrypoint {s}
        \\| entrypoint has not been found in the provided shader blob
    ;
};

pub const vertex_input_layout = struct {
    /// attribute binding,
    pub const non_zero_initial_offset =
        \\[VertexInputLayout] Binding {d}
        \\| attributes must begin at offset 0
    ;

    /// attribute index, attribute location, attribute binding,
    /// alignment, offset
    pub const unaligned_offset =
        \\[VertexInputLayout] Attribute {d} ({t}) at binding {d}
        \\| unsatisfied type alignment ({d} byte(s)) of offset {d}
    ;

    /// previous attribute index, previous attribute location, attribute index, attribute location, attribute binding,
    /// last offset, last end, assigned offset, current end
    pub const not_sequential =
        \\[VertexInputLayout] Attributes {d} ({t}) and {d} ({t}) at binding {d}
        \\| overlapping offsets: [{d}, {d}) and [{d}, {d})
    ;

    /// attribute index, attribute location, attribute binding,
    /// current offset, next offset, unaligned padding bytes
    pub const attribute_gap =
        \\[VertexInputLayout] Attribute {d} ({t}) at binding {d}
        \\| unsatisfied padding alignment (4 bytes) requirement within offsets {d} - {d} ({d} byte(s))
    ;

    /// attribute index, attribute location, attribute binding,
    /// unaligned padding bytes
    pub const end_gap =
        \\[VertexInputLayout] Binding {d}
        \\| unsatisfied padding alignment (4 bytes) requirement at the end ({d} bytes)
    ;

    /// attribute index, attribute location, attribute binding,
    /// alignment, stride
    pub const unaligned_stride =
        \\[VertexInputLayout] Binding {d}
        \\| unsatisfied stride alignment ({d} bytes) requirement with {d} bytes
    ;

    /// attribute index, attribute location, attribute binding,
    /// computed stride, stride
    pub const small_stride =
        \\[VertexInputLayout] Binding {d}
        \\| unsatisfied stride size ({d} bytes) requirement with {d} bytes
    ;
};

/// When validation is disabled returns a ZST
pub fn Data(comptime T: type) type {
    return if (enabled) T else void;
}

/// Initialize validation data which may be a ZST
pub fn init(comptime T: type, value: T) Data(T) {
    return if (enabled) value else {};
}

/// Emits an `error.ValidationFailed` when enabled, asserts on `ReleaseSmall` and `ReleaseFast` builds.
pub fn assert(condition: bool, comptime format: []const u8, args: anytype) Error!void {
    if (!check(condition, format, args)) {
        if (enabled) return error.ValidationFailed;

        // Basically: enable validation layers if you want to debug or have skill issues.
        // If you don't enable them you won't pay a penny for them.
        unreachable;
    }
}

/// Checks a condition, emmiting a log when enabled.
pub fn check(condition: bool, comptime format: []const u8, args: anytype) bool {
    if (enabled and !condition) {
        log.err(
            \\Validation Failed
            \\
        ++ format, args);
        return false;
    }

    return condition;
}

pub const log = blk: {
    const base = std.log.scoped(.mango);

    break :blk if (builtin.is_test) struct {
        pub const debug = base.debug;
        pub const info = base.info;
        pub const warn = base.warn;
        pub const err = base.warn;
    } else base;
};

const builtin = @import("builtin");
const std = @import("std");
