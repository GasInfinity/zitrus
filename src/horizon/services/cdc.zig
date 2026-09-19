//! CDC (Codec) control
//!
//! Based on 3dbrew:
//! - https://www.3dbrew.org/wiki/Codec_Services

pub const Hid = @import("cdc/Hid.zig");
pub const Mic = @import("cdc/Mic.zig");
pub const Legacy= @import("cdc/Legacy.zig");
pub const CSnd = @import("cdc/CSnd.zig");
pub const Dsp = @import("cdc/Dsp.zig");
pub const Check = @import("cdc/Check.zig");
