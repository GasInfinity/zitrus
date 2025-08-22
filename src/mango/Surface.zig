//! Wraps an LCD screen
//!
//! Currently surfaces are hardcoded values as a fixed set of DisplayModes is supported.
//! TODO: This could be augmented. Investigate lcd display modes.

pub const Handle = enum(u32) {
    null = 0,
    top_240x400,
    bottom_240x320,
    top_240x800,
};
