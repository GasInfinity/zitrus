pub const ProgramMeta = extern struct {
    const magic_value = "_prm";

    pub const RuntimeFlags = packed struct(u32) {
        apt_workaround: bool = false,
        apt_reinit: bool = false,
        apt_chainload: bool = false,
        _reserved: u29 = 0,

        pub fn isAptUnavailable(flags: RuntimeFlags) bool {
            return flags.apt_workaround and !flags.apt_reinit;
        }
    };

    magic: [magic_value.len]u8 = magic_value.*,
    provided_services: ?[*]u32 = null,
    app_id: Applet.AppId = .application,
    // Default: O3DS Heap size
    heap_size: u32 = 24 * 1024 * 1024,
    linear_heap_size: u32 = 32 * 1024 * 1024,
    argument_list: ?[*]u32 = null,
    runtime_flags: RuntimeFlags = RuntimeFlags{},

    pub fn isHomebrew(prm: ProgramMeta) bool {
        return prm.provided_services != null;
    }
};

pub var program_meta: ProgramMeta linksection(".prm") = .{};
pub var exit_fn: ?*const fn () noreturn = null;

const ProvidedService = struct {
    name: [8]u8,
    session: Session,
};

pub fn findService(name: []const u8) ?Session {
    if (program_meta.provided_services) |services_ptr| {
        const provided_services_size = @as(*u32, @ptrCast(services_ptr)).*;
        const provided_services = @as([*]ProvidedService, @ptrCast(services_ptr + 1))[0..provided_services_size];

        for (provided_services) |provided_service| {
            const service_name_len = std.mem.indexOf(u8, &provided_service.name, &[_]u8{0}).?;

            if (std.mem.eql(u8, provided_service.name[0..service_name_len], name)) {
                return provided_service.session;
            }
        }
    }

    return null;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const Session = horizon.Session;
const Applet = horizon.services.Applet;
