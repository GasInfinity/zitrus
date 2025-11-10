//! **L**ayout **An**imation
//!
//! Based on the documentation found in GBATEK:
//! * https://problemkaputt.de/gbatek.htm#3dsfilesvideolayoutanimationclanflan 

pub const magic = "CLAN";

pub const Pattern = extern struct {
    pub const Info = extern struct {
        _unknown0: [2]u32,
        entries: u32,
    };

    _unknown0: [4]u32,
    name: [16]u8,
};

