pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub const init_options: horizon.Init.Application.Software.Options = .{
    .double_buffer = .initFill(false),
};

pub fn main(init: horizon.Init.Application.Software) !void {
    const app = init.app;
    const soft = init.soft;
    const io = init.app.base.io;

    try horizon.Io.global.initStorage(app.srv, .fs, 0);
    try horizon.Io.global.mountSelfRomFs("romfs");

    const csnd: ChannelSound = try .open(app.srv);
    defer csnd.close();

    var engine: ChannelSound.Engine = try .initCapacity(csnd, 256);
    defer engine.deinit(csnd);

    var renderer_buf: [64]u8 = undefined;
    var top_renderer = zdebug.PsfRenderer.init(
        &renderer_buf,
        .bizcat,
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

    {
        var license_buf: [128]u8 = undefined;
        var license = try std.Io.Dir.cwd().openFile(io, "romfs:/LICENSE", .{});
        defer license.close(io);

        var license_reader = license.reader(io, &license_buf);
        _ = try license_reader.interface.streamRemaining(w);
        try w.writeAll("\nLoading full wav...\n");
        try w.flush();
    }

    var wave: WaveFile = blk: {
        var buf: [256]u8 = undefined;
        var file = try std.Io.Dir.cwd().openFile(io, "romfs:/sample-3s.wav", .{});
        defer file.close(io);

        var file_reader = file.reader(io, &buf);
        break :blk try .read(&file_reader.interface, horizon.heap.linear_page_allocator);
    };
    defer wave.deinit(horizon.heap.linear_page_allocator);

    try w.print("CSND allocated {d} channels to this process\n", .{engine.available_channels});
    try w.print("Allocated bitmask:\n {b:0>32}\n", .{@as(u32, @bitCast(engine.available_mask))});
    try w.print("Press A to play a sample sound directly\n", .{});
    try w.print("  Maintain L to ignore sleep state\n", .{});
    try w.print("  Maintain R to ignore volume slider\n", .{});
    try w.flush();
    soft.flush();

    var priority: u8 = 15;
    var last_current: horizon.services.Hid.Pad.State = std.mem.zeroes(horizon.services.Hid.Pad.State);
    var last_elapsed: u96 = 0;
    main_loop: while (true) {
        const start = horizon.time.getSystemNanoseconds();

        while (try init.app.pollEvent()) |ev| switch (ev) {
            .quit => break :main_loop,
            .jump_home_rejected => unreachable,
            .jump_home => {
                const capture = try init.soft.release(init.app.gsp);

                // Direct sounds seem cut off all DSP output (which home menu uses)
                try engine.stopDirect(csnd, .id(0));
                switch (try init.app.app.jumpToHome(init.app.apt, .app, init.app.srv, capture, .none)) {
                    .resumed => {
                        try init.soft.reacquire(init.app.gsp);
                        continue;
                    },
                    .jump_home => unreachable,
                    .must_close => break :main_loop,
                }
            },
            .sleep => {
                _ = try init.soft.release(init.app.gsp);
                while (try init.app.app.waitNotification(init.app.apt, .app, init.app.srv) != .sleep_wakeup) {}
                try init.soft.reacquire(init.app.gsp);
            },
        };

        const pad = app.input.pollPad();
        const changed = pad.current.changed(last_current);
        last_current = pad.current;

        const pressed = changed.same(pad.current);

        if (pad.current.start) break :main_loop;

        if (pressed.up or pressed.down) {
            priority += @intFromBool(pressed.up); 
            priority -|= @intFromBool(pressed.down);
            try w.print("P: {}, ", .{priority});
            try w.flush();
            soft.flush();
        }

        if (pressed.a) {
            _ = try engine.playDirect(csnd, .id(0), .priority(priority), &.{
                .stereo = wave.channels == 2,
                .channels = wave.channels,
                .format = .init(if (wave.pcm_bytes == 2) .pcm16 else .pcm8),
                .sample_rate = wave.samples_per_sec,
                .buffer = if (wave.channels == 2) .{
                    horizon.memory.toPhysical(@intFromPtr(wave.samples[0].ptr)),
                    horizon.memory.toPhysical(@intFromPtr(wave.samples[1].ptr)),
                } else @splat(horizon.memory.toPhysical(@intFromPtr(wave.samples[0].ptr))), 
                .size = wave.samples[0].len,
                .ima_state = undefined,
                .volume = @splat((std.math.maxInt(u16) / 3) * 2),
                .transition_gain = 0.2,
                .transition_time = 400,
                .ignore_sleep = pad.current.l,
                .ignore_volume_slider = pad.current.r,
            });
        }

        try soft.waitVBlank();

        const elapsed: u96 = horizon.time.getSystemNanoseconds() - start;
        last_elapsed = elapsed;
    }

    // I'm sure you want to stop the sound unless you want to play garbage,
    // if so; go all in!
    try engine.stopDirect(csnd, .id(0));
}

const WaveFile = struct {
    const RiffHeader = extern struct {
        id: [4]u8,
        size: u32,
        fmt: [4]u8,
    };

    const Chunk = extern struct {
        const Format = extern struct {
            fmt: u16,
            channels: u16,
            samples_per_sec: u32,
            avg_bytes_per_sec: u32,
            block_align: u16,
            pcm_bits: u16,
        };

        id: [4]u8,
        size: u32,
    };

    channels: u8,
    pcm_bytes: u8,
    samples_per_sec: u32,
    samples: [2][]u8,

    pub fn read(reader: *std.Io.Reader, linear_gpa: std.mem.Allocator) !WaveFile {
        const riff = try reader.takeStruct(RiffHeader, .little);
        if (!std.mem.eql(u8, &riff.id, "RIFF")) return error.NotWav;
        if (!std.mem.eql(u8, &riff.fmt, "WAVE")) return error.NotWav;

        var channels: u8 = 0;
        var pcm_bytes: u8 = 0;
        var samples_per_sec: u32 = 0;
        var samples: [2][]u8 = @splat(&.{});
        errdefer for (&samples) |buffer| linear_gpa.free(buffer);

        while (true) {
            const chunk = reader.takeStruct(Chunk, .little) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };

            if (std.mem.eql(u8, &chunk.id, "fmt ")) {
                const fmt = try reader.takeStruct(Chunk.Format, .little);

                if (fmt.fmt != 1) return error.UnsupportedWav;
                if (fmt.channels > 2 or fmt.channels == 0) return error.UnsupportedWav;

                channels = @intCast(fmt.channels);
                samples_per_sec = fmt.samples_per_sec;

                if (fmt.pcm_bits != 8 and fmt.pcm_bits != 16) return error.UnsupportedWav;

                pcm_bytes = @intCast(fmt.pcm_bits / 8);
            } else if (std.mem.eql(u8, &chunk.id, "data")) {
                if (channels == 0) return error.UnsupportedWav;
                const bytes_per_channel = chunk.size / channels;

                for (samples[0..2]) |*data| data.* = try linear_gpa.alloc(u8, bytes_per_channel * pcm_bytes);

                var i: usize = 0;
                var remaining = chunk.size;
                var buf: [512]u8 = undefined;

                while (remaining > 0) {
                    const reading = buf[0..@min(512, remaining)];
                    try reader.readSliceAll(reading);

                    var current: usize = 0;
                    while (current < reading.len) : (current += channels * pcm_bytes) {
                        for (0..channels) |chn| {
                            for (0..pcm_bytes) |byte| samples[chn][i + byte] = reading[current + byte + chn * pcm_bytes];
                        }
                        i += pcm_bytes;
                    }

                    remaining -= reading.len;
                }
            }
        }

        if (channels == 0) return error.NotWav;

        return .{
            .channels = channels,
            .pcm_bytes = pcm_bytes,
            .samples_per_sec = samples_per_sec,
            .samples = samples,
        };
    }

    pub fn deinit(wave: *WaveFile, linear_gpa: std.mem.Allocator) void {
        for (wave.samples[0..wave.channels]) |samples| linear_gpa.free(samples);
    }
};

const horizon = zitrus.horizon;
const environment = zitrus.horizon.environment;
const Gpu = horizon.services.gsp.Gpu;
const ChannelSound = horizon.services.ChannelSound;

const zdebug = zitrus.debug;
const zitrus = @import("zitrus");
const std = @import("std");
