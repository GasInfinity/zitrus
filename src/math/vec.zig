pub fn dot(comptime len: usize, comptime T: type, a: @Vector(len, T), b: @Vector(len, T)) T {
    return @reduce(.Add, @as(@Vector(len, T), a) * @as(@Vector(len, T), b));
}

pub fn lengthSqr(comptime len: usize, comptime T: type, a: @Vector(len, T)) T {
    return dot(len, T, a, a);
}

pub fn length(comptime len: usize, comptime T: type, a: @Vector(len, T)) T {
    return @sqrt(lengthSqr(len, T, a));
}

/// Returns the normalized vector and the vector length.
pub fn normalize(comptime len: usize, comptime T: type, a: @Vector(len, T)) struct { @Vector(len, T), T } {
    const v_length = length(len, T, a);

    return .{ (@as(@Vector(len, T), a) / @as(@Vector(len, T), @splat(v_length))), v_length };
}

/// Cross product between two 3-dimensional vectors.
///
/// |i j k|
/// |x y z| = (yw - zv)i + (zu - xw)j + (xv - yu)k
/// |u v w|
///
pub fn cross(comptime T: type, a: @Vector(3, T), b: @Vector(3, T)) @Vector(3, T) {
    const fa_vec: @Vector(3, T) = @shuffle(T, a, a, [_]i32{ 1, 2, 0 });
    const sa_vec: @Vector(3, T) = @shuffle(T, a, a, [_]i32{ 2, 0, 1 });

    const fb_vec: @Vector(3, T) = @shuffle(T, b, b, [_]i32{ 1, 2, 0 });
    const sb_vec: @Vector(3, T) = @shuffle(T, b, b, [_]i32{ 2, 0, 1 });

    return (fa_vec * sb_vec) - (sa_vec * fb_vec);
}
