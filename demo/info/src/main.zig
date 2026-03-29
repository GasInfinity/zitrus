pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub const init_options: horizon.Init.Application.Software.Options = .{
    .double_buffer = .initFill(false),
};

pub fn main(init: horizon.Init.Application.Software) !void {
    const app = init.app;
    const gpa = app.base.gpa;
    const io = app.base.io;
    const soft = init.soft;

    try horizon.Io.global.initStorage(app.srv, .fs, 0);
    try horizon.Io.global.mountSelfRomFs("romfs");

    const cfg = try Config.open(.user, app.srv);
    defer cfg.close();

    // NOTE: The font is available by default but we're also showing how loading it from the RomFS works.
    // const psf: zdebug.PsfRenderer.Font = .bizcat;
    const bizcat = try std.Io.Dir.cwd().readFileAlloc(io, "romfs:/bizcat.psfu", gpa, .unlimited);
    defer gpa.free(bizcat);

    // We only want ASCII
    var unicode_map_buffer: [256]u32 = undefined;
    const psf: zdebug.PsfRenderer.Font = try .init(&unicode_map_buffer, bizcat);
    defer psf.deinit(gpa);

    var renderer_buf: [64]u8 = undefined;
    var top_renderer = try zdebug.PsfRenderer.init(
        &renderer_buf,
        psf,
        soft.current(.top, .left),
        240 * 3,
        0,
        0,
        400,
        240,
        3,
    );
    top_renderer.clear();

    const w = &top_renderer.writer;
    const model = try cfg.sendGetSystemModel();

    const name_info = try cfg.getConfigUser(.user_name);
    const language = try cfg.getConfigUser(.language);
    const birthday = try cfg.getConfigUser(.birthday);
    const country_info = try cfg.getConfigUser(.country_info);
    const region = try cfg.sendGetRegion();

    try w.print("3DSX? {}\n", .{environment.program_meta.is3dsx()});
    try w.print("Model: {t} ({s})\n", .{model, model.description()});
    try w.print("Region: {t}\n", .{region});
    try w.print("Name: {f}\n", .{std.unicode.fmtUtf16Le(name_info.name[0..std.mem.findScalar(u16, &name_info.name, 0) orelse name_info.name.len])});
    try w.print("Language: {t}\n", .{language});
    try w.print("Birthday: {}/{}\n", .{birthday.day, birthday.month});
    try w.print("Country: {}/{}\n", .{country_info.province_code, country_info.country_code});
    try w.print("Base: {} | Total: {!}\n", .{ std.process.getBaseAddress(), std.process.totalSystemMemory() });

    try w.writeAll("Arguments: ");
    var arg_it = environment.program_meta.argumentListIterator();

    while (arg_it.next()) |arg| try w.print("{s} ", .{arg});
    try w.writeAll(";\n");
    try w.flush();

    var last_elapsed: u96 = 0;
    main_loop: while (true) {
        const start = horizon.time.getSystemNanoseconds();

        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        soft.flush();
        soft.swap(.none);
        try soft.waitVBlank();

        const elapsed: u96 = horizon.time.getSystemNanoseconds() - start;
        last_elapsed = elapsed;
    }
}

const horizon = zitrus.horizon;
const environment = zitrus.horizon.environment;
const GspGpu = horizon.services.GspGpu;

const Config = horizon.services.Config;

const zdebug = zitrus.debug;
const zitrus = @import("zitrus");
const std = @import("std");
