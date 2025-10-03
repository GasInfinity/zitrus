//! Useful matrix operations.
//!
//! They all transform to the PICA200 NDC volume (Same as OpenGL/VK/D3D except Z [0, -1]).
//! If you already have a matrix which expects a VK/D3D Z [0, 1] and don't want to use
//! these helpers, you can negate m33 and m34
//!
//! Some operations are provided for the sake of completeness (translation, scale, ...)

pub const Handedness = enum(i2) {
    left = 1,
    right = -1,
};

pub const @"4x4" = [4][4]f32;

pub fn transpose(comptime n: usize, comptime T: type, a: [n][n]T) [n][n]T {
    var result: [n][n]T = undefined;

    for (0..n) |i| for (i..n) |j| {
        result[n * i + j] = a[n * j + i];
    };

    return result;
}

pub fn translate(x: f32, y: f32, z: f32) @"4x4" {
    return .{
        .{ 1, 0, 0, x },
        .{ 0, 1, 0, y },
        .{ 0, 0, 1, z },
        .{ 0, 0, 0, 1 },
    };
}

pub fn scale(x: f32, y: f32, z: f32) @"4x4" {
    return .{
        .{ x, 0, 0, 0 },
        .{ 0, y, 0, 0 },
        .{ 0, 0, z, 0 },
        .{ 0, 0, 0, 1 },
    };
}

/// Rotation matrix of a quaternion.
pub fn rotate(x: f32, y: f32, z: f32, w: f32) @"4x4" {
    const xx = x * x;
    const yy = y * y;
    const zz = z * z;

    const xy = x * y;
    const xz = x * z;
    const xw = x * w;

    const yz = y * z;
    const yw = y * w;

    const zw = z * w;

    const ww = w * w;

    return .{
        .{ 2 * (xx + ww) - 1, 2 * (xy - zw), 2 * (xz + yw), 0 },
        .{ 2 * (xy + zw), 2 * (yy + ww) - 1, 2 * (yz - xw), 0 },
        .{ 2 * (xz - yw), 2 * (yz + xw), 2 * (zz + ww) - 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

/// Same operation as if you first scale and then translate.
pub fn scaleTranslate(sx: f32, sy: f32, sz: f32, x: f32, y: f32, z: f32) @"4x4" {
    return .{
        .{ sx, 0, 0, x },
        .{ 0, sy, 0, y },
        .{ 0, 0, sz, z },
        .{ 0, 0, 0, 1 },
    };
}

/// Same operation as if you first scale, then rotate and then translate.
///
/// Translation and scale are 3-dimensional vectors.
/// Rotation is a quaternion.
pub fn scaleRotateTranslate(
    sx: f32,
    sy: f32,
    sz: f32,
    rx: f32,
    ry: f32,
    rz: f32,
    rw: f32,
    tx: f32,
    ty: f32,
    tz: f32,
) @"4x4" {
    const rxx = rx * rx;
    const rxy = rx * ry;
    const rxz = rx * rz;
    const rxw = rx * rw;

    const ryy = ry * ry;
    const ryz = ry * rz;
    const ryw = ry * rw;

    const rzz = rz * rz;
    const rzw = rz * rw;

    const rww = rw * rw;

    return .{
        .{ sx * (2 * (rxx + rww) - 1), sx * 2 * (rxy - rzw), sx * 2 * (rxz + ryw), tx },
        .{ sy * 2 * (rxy + rzw), sy * (2 * (ryy + rww) - 1), sy * 2 * (ryz - rxw), ty },
        .{ sz * 2 * (rxz - ryw), sz * 2 * (ryz + rxw), sz * (2 * (rzz + rww) - 1), tz },
        .{ 0, 0, 0, 1 },
    };
}

/// Same as `scaleRotateTranslate` but with parameters as vectors / quaternions.
pub fn scaleRotateTranslateV(s: [3]f32, r: [4]f32, t: [3]f32) @"4x4" {
    return scaleRotateTranslate(s[0], s[1], s[2], r[0], r[1], r[2], r[3], t[0], t[1], t[2]);
}

// TODO: right-handed ortho
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

pub fn persp(comptime handedness: Handedness, fov_y: f32, aspect_ratio: f32, n: f32, f: f32) @"4x4" {
    const handedness_factor: comptime_float = @floatFromInt(@intFromEnum(handedness));
    const fov_y_tan = @tan(fov_y / 2.0);
    const f_range = f - n;

    return .{
        .{ 1 / (fov_y_tan * aspect_ratio), 0, 0, 0 },
        .{ 0, 1 / fov_y_tan, 0, 0 },
        .{ 0, 0, handedness_factor * (-f / f_range), ((f * n) / f_range) },
        .{ 0, 0, handedness_factor * 1, 0 },
    };
}

pub fn perspRotate90Cw(comptime handedness: Handedness, fov_y: f32, aspect_ratio: f32, n: f32, f: f32) @"4x4" {
    const handedness_factor: comptime_float = @floatFromInt(@intFromEnum(handedness));
    const fov_y_tan = @tan(fov_y / 2.0);
    const f_range = f - n;

    return .{
        .{ 0, 1 / fov_y_tan, 0, 0 },
        .{ -aspect_ratio / fov_y_tan, 0, 0, 0 },
        .{ 0, 0, handedness_factor * (-f / f_range), ((f * n) / f_range) },
        .{ 0, 0, handedness_factor * 1, 0 },
    };
}

const std = @import("std");

const zitrus = @import("zitrus");
const math = zitrus.math;
