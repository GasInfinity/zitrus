//! Quaternion utilities. The real part is the last element.

pub fn euler(comptime T: type, x: T, y: T, z: T) @Vector(4, T) {
    const sx = @sin(x / 2.0);
    const cx = @cos(x / 2.0);

    const sy = @sin(y / 2.0);
    const cy = @cos(y / 2.0);

    const sz = @sin(z / 2.0);
    const cz = @cos(z / 2.0);

    return .{
        cx * cy * cz + sx * sy * sz,
        sx * cy * cz - cx * sy * sz,
        cx * sy * cz + sx * cy * sz,
        cx * cy * sz - sx * sy * cz,
    };
}

/// Same as `euler` but with a vector instead of scalars.
pub fn eulerV(comptime T: type, v: @Vector(3, T)) @Vector(4, T) {
    return euler(T, v[0], v[1], v[2]);
}

/// Constructs a quaternion from an axis `a` and a normalized angle `x`, `y`, `z`.
pub fn axisAngle(comptime T: type, x: T, y: T, z: T, a: T) @Vector(4, T) {
    const h_sin = @sin(a / 2.0);
    const h_cos = @cos(a / 2.0);

    return .{ x * h_sin, y * h_sin, z * h_sin, h_cos };
}

/// Same as `axisAngle` but axis is a vector instead of scalars.
pub fn axisAngleV(comptime T: type, axis: @Vector(3, T), angle: T) [4]T {
    const h_sin: @Vector(3, T) = @splat(@sin(angle / 2.0));
    const h_cos: @Vector(3, T) = @splat(@cos(angle / 2.0));

    return @shuffle(T, axis * h_sin, h_cos, [_]i32{ 0, 1, 2, -1 });
}

const zitrus = @import("zitrus");
const math = zitrus.math;
