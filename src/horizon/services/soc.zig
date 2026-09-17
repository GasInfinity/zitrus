//! Socket services
//!
//! Note that blocking calls will block the session and other threads trying to use it.
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Socket_Services

pub const User = @import("soc/User.zig");
