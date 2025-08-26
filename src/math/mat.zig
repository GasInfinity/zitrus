//! Useful matrix operations.
//!
//! They all transform to the PICA200 NDC volume (Same as OpenGL except Z [0, -1])
//!
//! Some operations are provided for the sake of completeness (translation, scale, ...)

pub const @"4x4" = [4][4]f32;

pub fn translate(x: f32, y: f32, z: f32) @"4x4" {
    return .{
        .{1, 0, 0, x},
        .{0, 1, 0, y},
        .{0, 0, 1, z},
        .{0, 0, 0, 1},
    };
}

pub fn scale(x: f32, y: f32, z: f32) @"4x4" {
    return .{
        .{x, 0, 0, 0},
        .{0, y, 0, 0},
        .{0, 0, z, 0},
        .{0, 0, 0, 1},
    };
}

pub fn ortho(l: f32, t: f32, r: f32, b: f32, n: f32, f: f32) @"4x4" {
    const x_scale = r - l;
    const y_scale = b - t;
    const z_scale = n - f;

    return .{
        .{ 2 / x_scale, 0, 0, -(r + l) / x_scale },
        .{ 0, 2 / y_scale, 0, -(b + t) / y_scale },
        .{ 0, 0, 1 / z_scale, -n / z_scale },
        .{ 0, 0, 0, 1 },
    };
}

pub fn orthoRotate90Cw(l: f32, t: f32, r: f32, b: f32, n: f32, f: f32) @"4x4" {
    const x_scale = r - l;
    const y_scale = b - t;
    const z_scale = n - f;

    return .{
        .{ 0, 2 / y_scale, 0, -(b + t) / y_scale },
        .{ -2 / x_scale, 0, 0, (r + l) / x_scale },
        .{ 0, 0, 1 / z_scale, -n / z_scale },
        .{ 0, 0, 0, 1 },
    };
}

pub fn persp(fov_y: f32, aspect_ratio: f32, n: f32, f: f32) @"4x4" {
    const fov_y_tan = @tan(fov_y / 2.0);
    const f_range = f - n;

    return .{
        .{ 1 / (fov_y_tan * aspect_ratio), 0, 0, 0 },
        .{ 0, 1 / fov_y_tan, 0, 0 },
        .{ 0, 0, -f / f_range, (f * n) / f_range },
        .{ 0, 0, 1, 0 },
    };
}

pub fn perspRotate90Cw(fov_y: f32, aspect_ratio: f32, n: f32, f: f32) @"4x4" {
    const fov_y_tan = @tan(fov_y / 2.0);
    const f_range = f - n;

    return .{
        .{ 0, 1 / fov_y_tan, 0, 0 },
        .{ -1 / (fov_y_tan * aspect_ratio), 0, 0, 0 },
        .{ 0, 0, -f / f_range, (f * n) / f_range },
        .{ 0, 0, 1, 0 },
    };
}
