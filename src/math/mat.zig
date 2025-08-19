//! Useful matrix operations.
//!
//! They all transform to the PICA200 NDC volume (Same as OpenGL except Z [0, -1])
pub const @"4x4" = [4][4]f32;

pub fn ortho(l: f32, t: f32, r: f32, b: f32, n: f32, f: f32) @"4x4" {
    const x_scale = r - l;
    const y_scale = b - t;
    const z_scale = n - f;

    return .{
        .{2 / x_scale, 0, 0, -(r + l) / x_scale},
        .{0, 2 / y_scale, 0, -(b + t) / y_scale},
        .{0, 0, 1 / z_scale, -n / z_scale},
        .{0, 0, 0, 1},
    };
}

pub fn orthoRotate90Cw(l: f32, t: f32, r: f32, b: f32, n: f32, f: f32) @"4x4" {
    const x_scale = r - l;
    const y_scale = b - t;
    const z_scale = n - f;

    return .{
        .{0, 2 / y_scale, 0, -(b + t) / y_scale},
        .{-2 / x_scale, 0, 0, (r + l) / x_scale},
        .{0, 0, 1 / z_scale, -n / z_scale},
        .{0, 0, 0, 1},
    };
}
