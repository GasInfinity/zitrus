pub const Component = enum(u2) {
    const span = "xyzw";

    x,
    y,
    z,
    w,

    pub const Mask = packed struct(u4) {
        pub const x: Mask = .{ .enable_x = true };
        pub const y: Mask = .{ .enable_y = true };
        pub const z: Mask = .{ .enable_z = true };
        pub const w: Mask = .{ .enable_w = true };
        pub const xy: Mask = .{ .enable_x = true, .enable_y = true };
        pub const xz: Mask = .{ .enable_x = true, .enable_z = true };
        pub const xw: Mask = .{ .enable_x = true, .enable_w = true };
        pub const yz: Mask = .{ .enable_y = true, .enable_z = true };
        pub const yw: Mask = .{ .enable_y = true, .enable_w = true };
        pub const zw: Mask = .{ .enable_z = true, .enable_w = true };
        pub const xyz: Mask = .{ .enable_x = true, .enable_y = true, .enable_z = true };
        pub const xzw: Mask = .{ .enable_x = true, .enable_z = true, .enable_w = true };
        pub const yzw: Mask = .{ .enable_y = true, .enable_z = true, .enable_w = true };
        pub const xyzw: Mask = .{ .enable_x = true, .enable_y = true, .enable_z = true, .enable_w = true };

        enable_x: bool = false,
        enable_y: bool = false,
        enable_z: bool = false,
        enable_w: bool = false,

        pub fn size(mask: Mask) usize {
            return (((@as(usize, @intFromBool(mask.enable_x)) + @intFromBool(mask.enable_y)) + @intFromBool(mask.enable_z)) + @intFromBool(mask.enable_w));
        }

        pub const ParseError = error{
            Syntax,
            InvalidMask,
            InvalidComponent,
        };

        pub fn parse(value: []const u8) ParseError!Mask {
            if(value.len == 0 or value.len > 4) {
                return error.Syntax;
            }

            var last: ?usize = null;
            var mask: u4 = 0;
            for (value) |c| {
                const component = std.mem.indexOf(u8, span, &.{c}) orelse return error.InvalidComponent;

                if(last) |l| {
                    if(component <= l) {
                        return error.InvalidMask;
                    }
                }

                mask |= @as(u4, 1) << @intCast(component);
                last = component;
            }

            return @bitCast(mask);
        }

        test parse {
            try testing.expectEqual(Mask.xyzw, try parse("xyzw"));
            try testing.expectEqual(Mask.w, try parse("w"));
            try testing.expectEqual(Mask.yw, try parse("yw"));
            try testing.expectEqual(Mask.yzw, try parse("yzw"));
            try testing.expectError(error.InvalidMask, parse("zyx"));
            try testing.expectError(error.InvalidMask, parse("wy"));
            try testing.expectError(error.InvalidMask, parse("xxxx"));
            try testing.expectError(error.InvalidMask, parse("wyxz"));
        }
    };

    pub const Selector = packed struct(u8) {
        pub const x: Selector = .{ .@"0" = .x };
        pub const y: Selector = .{ .@"0" = .y };
        pub const z: Selector = .{ .@"0" = .z };
        pub const w: Selector = .{ .@"0" = .w };
        pub const xx: Selector = .{ .@"0" = .x, .@"1" = .x };
        pub const xy: Selector = .{ .@"0" = .x, .@"1" = .y };
        pub const xz: Selector = .{ .@"0" = .x, .@"1" = .z };
        pub const xw: Selector = .{ .@"0" = .x, .@"1" = .w };
        pub const yx: Selector = .{ .@"0" = .y, .@"1" = .x };
        pub const yy: Selector = .{ .@"0" = .y, .@"1" = .y };
        pub const yz: Selector = .{ .@"0" = .y, .@"1" = .z };
        pub const yw: Selector = .{ .@"0" = .y, .@"1" = .w };
        pub const zx: Selector = .{ .@"0" = .z, .@"1" = .x };
        pub const zy: Selector = .{ .@"0" = .z, .@"1" = .y };
        pub const zz: Selector = .{ .@"0" = .z, .@"1" = .z };
        pub const zw: Selector = .{ .@"0" = .z, .@"1" = .w };
        pub const wx: Selector = .{ .@"0" = .w, .@"1" = .x };
        pub const wy: Selector = .{ .@"0" = .w, .@"1" = .y };
        pub const wz: Selector = .{ .@"0" = .w, .@"1" = .z };
        pub const ww: Selector = .{ .@"0" = .w, .@"1" = .w };
        pub const xxx: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .x };
        pub const xxy: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .y };
        pub const xxz: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .z };
        pub const xxw: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .w };
        pub const xyx: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .x };
        pub const xyy: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .y };
        pub const xyz: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .z };
        pub const xyw: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .w };
        pub const xzx: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .x };
        pub const xzy: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .y };
        pub const xzz: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .z };
        pub const xzw: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .w };
        pub const xwx: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .x };
        pub const xwy: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .y };
        pub const xwz: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .z };
        pub const xww: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .w };
        pub const yxx: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .x };
        pub const yxy: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .y };
        pub const yxz: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .z };
        pub const yxw: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .w };
        pub const yyx: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .x };
        pub const yyy: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .y };
        pub const yyz: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .z };
        pub const yyw: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .w };
        pub const yzx: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .x };
        pub const yzy: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .y };
        pub const yzz: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .z };
        pub const yzw: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .w };
        pub const ywx: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .x };
        pub const ywy: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .y };
        pub const ywz: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .z };
        pub const yww: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .w };
        pub const zxx: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .x };
        pub const zxy: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .y };
        pub const zxz: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .z };
        pub const zxw: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .w };
        pub const zyx: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .x };
        pub const zyy: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .y };
        pub const zyz: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .z };
        pub const zyw: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .w };
        pub const zzx: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .x };
        pub const zzy: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .y };
        pub const zzz: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .z };
        pub const zzw: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .w };
        pub const zwx: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .x };
        pub const zwy: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .y };
        pub const zwz: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .z };
        pub const zww: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .w };
        pub const wxx: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .x };
        pub const wxy: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .y };
        pub const wxz: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .z };
        pub const wxw: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .w };
        pub const wyx: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .x };
        pub const wyy: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .y };
        pub const wyz: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .z };
        pub const wyw: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .w };
        pub const wzx: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .x };
        pub const wzy: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .y };
        pub const wzz: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .z };
        pub const wzw: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .w };
        pub const wwx: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .x };
        pub const wwy: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .y };
        pub const wwz: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .z };
        pub const www: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .w };
        pub const xxxx: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .x, .@"3" = .x };
        pub const xxxy: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .x, .@"3" = .y };
        pub const xxxz: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .x, .@"3" = .z };
        pub const xxxw: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .x, .@"3" = .w };
        pub const xxyx: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .y, .@"3" = .x };
        pub const xxyy: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .y, .@"3" = .y };
        pub const xxyz: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .y, .@"3" = .z };
        pub const xxyw: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .y, .@"3" = .w };
        pub const xxzx: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .z, .@"3" = .x };
        pub const xxzy: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .z, .@"3" = .y };
        pub const xxzz: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .z, .@"3" = .z };
        pub const xxzw: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .z, .@"3" = .w };
        pub const xxwx: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .w, .@"3" = .x };
        pub const xxwy: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .w, .@"3" = .y };
        pub const xxwz: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .w, .@"3" = .z };
        pub const xxww: Selector = .{ .@"0" = .x, .@"1" = .x, .@"2" = .w, .@"3" = .w };
        pub const xyxx: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .x, .@"3" = .x };
        pub const xyxy: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .x, .@"3" = .y };
        pub const xyxz: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .x, .@"3" = .z };
        pub const xyxw: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .x, .@"3" = .w };
        pub const xyyx: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .y, .@"3" = .x };
        pub const xyyy: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .y, .@"3" = .y };
        pub const xyyz: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .y, .@"3" = .z };
        pub const xyyw: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .y, .@"3" = .w };
        pub const xyzx: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .z, .@"3" = .x };
        pub const xyzy: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .z, .@"3" = .y };
        pub const xyzz: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .z, .@"3" = .z };
        pub const xyzw: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .z, .@"3" = .w };
        pub const xywx: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .w, .@"3" = .x };
        pub const xywy: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .w, .@"3" = .y };
        pub const xywz: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .w, .@"3" = .z };
        pub const xyww: Selector = .{ .@"0" = .x, .@"1" = .y, .@"2" = .w, .@"3" = .w };
        pub const xzxx: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .x, .@"3" = .x };
        pub const xzxy: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .x, .@"3" = .y };
        pub const xzxz: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .x, .@"3" = .z };
        pub const xzxw: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .x, .@"3" = .w };
        pub const xzyx: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .y, .@"3" = .x };
        pub const xzyy: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .y, .@"3" = .y };
        pub const xzyz: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .y, .@"3" = .z };
        pub const xzyw: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .y, .@"3" = .w };
        pub const xzzx: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .z, .@"3" = .x };
        pub const xzzy: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .z, .@"3" = .y };
        pub const xzzz: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .z, .@"3" = .z };
        pub const xzzw: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .z, .@"3" = .w };
        pub const xzwx: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .w, .@"3" = .x };
        pub const xzwy: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .w, .@"3" = .y };
        pub const xzwz: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .w, .@"3" = .z };
        pub const xzww: Selector = .{ .@"0" = .x, .@"1" = .z, .@"2" = .w, .@"3" = .w };
        pub const xwxx: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .x, .@"3" = .x };
        pub const xwxy: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .x, .@"3" = .y };
        pub const xwxz: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .x, .@"3" = .z };
        pub const xwxw: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .x, .@"3" = .w };
        pub const xwyx: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .y, .@"3" = .x };
        pub const xwyy: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .y, .@"3" = .y };
        pub const xwyz: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .y, .@"3" = .z };
        pub const xwyw: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .y, .@"3" = .w };
        pub const xwzx: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .z, .@"3" = .x };
        pub const xwzy: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .z, .@"3" = .y };
        pub const xwzz: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .z, .@"3" = .z };
        pub const xwzw: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .z, .@"3" = .w };
        pub const xwwx: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .w, .@"3" = .x };
        pub const xwwy: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .w, .@"3" = .y };
        pub const xwwz: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .w, .@"3" = .z };
        pub const xwww: Selector = .{ .@"0" = .x, .@"1" = .w, .@"2" = .w, .@"3" = .w };
        pub const yxxx: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .x, .@"3" = .x };
        pub const yxxy: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .x, .@"3" = .y };
        pub const yxxz: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .x, .@"3" = .z };
        pub const yxxw: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .x, .@"3" = .w };
        pub const yxyx: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .y, .@"3" = .x };
        pub const yxyy: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .y, .@"3" = .y };
        pub const yxyz: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .y, .@"3" = .z };
        pub const yxyw: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .y, .@"3" = .w };
        pub const yxzx: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .z, .@"3" = .x };
        pub const yxzy: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .z, .@"3" = .y };
        pub const yxzz: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .z, .@"3" = .z };
        pub const yxzw: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .z, .@"3" = .w };
        pub const yxwx: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .w, .@"3" = .x };
        pub const yxwy: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .w, .@"3" = .y };
        pub const yxwz: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .w, .@"3" = .z };
        pub const yxww: Selector = .{ .@"0" = .y, .@"1" = .x, .@"2" = .w, .@"3" = .w };
        pub const yyxx: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .x, .@"3" = .x };
        pub const yyxy: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .x, .@"3" = .y };
        pub const yyxz: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .x, .@"3" = .z };
        pub const yyxw: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .x, .@"3" = .w };
        pub const yyyx: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .y, .@"3" = .x };
        pub const yyyy: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .y, .@"3" = .y };
        pub const yyyz: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .y, .@"3" = .z };
        pub const yyyw: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .y, .@"3" = .w };
        pub const yyzx: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .z, .@"3" = .x };
        pub const yyzy: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .z, .@"3" = .y };
        pub const yyzz: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .z, .@"3" = .z };
        pub const yyzw: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .z, .@"3" = .w };
        pub const yywx: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .w, .@"3" = .x };
        pub const yywy: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .w, .@"3" = .y };
        pub const yywz: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .w, .@"3" = .z };
        pub const yyww: Selector = .{ .@"0" = .y, .@"1" = .y, .@"2" = .w, .@"3" = .w };
        pub const yzxx: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .x, .@"3" = .x };
        pub const yzxy: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .x, .@"3" = .y };
        pub const yzxz: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .x, .@"3" = .z };
        pub const yzxw: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .x, .@"3" = .w };
        pub const yzyx: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .y, .@"3" = .x };
        pub const yzyy: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .y, .@"3" = .y };
        pub const yzyz: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .y, .@"3" = .z };
        pub const yzyw: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .y, .@"3" = .w };
        pub const yzzx: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .z, .@"3" = .x };
        pub const yzzy: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .z, .@"3" = .y };
        pub const yzzz: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .z, .@"3" = .z };
        pub const yzzw: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .z, .@"3" = .w };
        pub const yzwx: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .w, .@"3" = .x };
        pub const yzwy: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .w, .@"3" = .y };
        pub const yzwz: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .w, .@"3" = .z };
        pub const yzww: Selector = .{ .@"0" = .y, .@"1" = .z, .@"2" = .w, .@"3" = .w };
        pub const ywxx: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .x, .@"3" = .x };
        pub const ywxy: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .x, .@"3" = .y };
        pub const ywxz: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .x, .@"3" = .z };
        pub const ywxw: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .x, .@"3" = .w };
        pub const ywyx: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .y, .@"3" = .x };
        pub const ywyy: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .y, .@"3" = .y };
        pub const ywyz: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .y, .@"3" = .z };
        pub const ywyw: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .y, .@"3" = .w };
        pub const ywzx: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .z, .@"3" = .x };
        pub const ywzy: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .z, .@"3" = .y };
        pub const ywzz: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .z, .@"3" = .z };
        pub const ywzw: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .z, .@"3" = .w };
        pub const ywwx: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .w, .@"3" = .x };
        pub const ywwy: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .w, .@"3" = .y };
        pub const ywwz: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .w, .@"3" = .z };
        pub const ywww: Selector = .{ .@"0" = .y, .@"1" = .w, .@"2" = .w, .@"3" = .w };
        pub const zxxx: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .x, .@"3" = .x };
        pub const zxxy: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .x, .@"3" = .y };
        pub const zxxz: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .x, .@"3" = .z };
        pub const zxxw: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .x, .@"3" = .w };
        pub const zxyx: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .y, .@"3" = .x };
        pub const zxyy: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .y, .@"3" = .y };
        pub const zxyz: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .y, .@"3" = .z };
        pub const zxyw: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .y, .@"3" = .w };
        pub const zxzx: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .z, .@"3" = .x };
        pub const zxzy: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .z, .@"3" = .y };
        pub const zxzz: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .z, .@"3" = .z };
        pub const zxzw: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .z, .@"3" = .w };
        pub const zxwx: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .w, .@"3" = .x };
        pub const zxwy: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .w, .@"3" = .y };
        pub const zxwz: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .w, .@"3" = .z };
        pub const zxww: Selector = .{ .@"0" = .z, .@"1" = .x, .@"2" = .w, .@"3" = .w };
        pub const zyxx: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .x, .@"3" = .x };
        pub const zyxy: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .x, .@"3" = .y };
        pub const zyxz: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .x, .@"3" = .z };
        pub const zyxw: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .x, .@"3" = .w };
        pub const zyyx: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .y, .@"3" = .x };
        pub const zyyy: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .y, .@"3" = .y };
        pub const zyyz: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .y, .@"3" = .z };
        pub const zyyw: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .y, .@"3" = .w };
        pub const zyzx: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .z, .@"3" = .x };
        pub const zyzy: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .z, .@"3" = .y };
        pub const zyzz: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .z, .@"3" = .z };
        pub const zyzw: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .z, .@"3" = .w };
        pub const zywx: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .w, .@"3" = .x };
        pub const zywy: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .w, .@"3" = .y };
        pub const zywz: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .w, .@"3" = .z };
        pub const zyww: Selector = .{ .@"0" = .z, .@"1" = .y, .@"2" = .w, .@"3" = .w };
        pub const zzxx: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .x, .@"3" = .x };
        pub const zzxy: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .x, .@"3" = .y };
        pub const zzxz: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .x, .@"3" = .z };
        pub const zzxw: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .x, .@"3" = .w };
        pub const zzyx: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .y, .@"3" = .x };
        pub const zzyy: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .y, .@"3" = .y };
        pub const zzyz: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .y, .@"3" = .z };
        pub const zzyw: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .y, .@"3" = .w };
        pub const zzzx: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .z, .@"3" = .x };
        pub const zzzy: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .z, .@"3" = .y };
        pub const zzzz: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .z, .@"3" = .z };
        pub const zzzw: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .z, .@"3" = .w };
        pub const zzwx: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .w, .@"3" = .x };
        pub const zzwy: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .w, .@"3" = .y };
        pub const zzwz: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .w, .@"3" = .z };
        pub const zzww: Selector = .{ .@"0" = .z, .@"1" = .z, .@"2" = .w, .@"3" = .w };
        pub const zwxx: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .x, .@"3" = .x };
        pub const zwxy: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .x, .@"3" = .y };
        pub const zwxz: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .x, .@"3" = .z };
        pub const zwxw: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .x, .@"3" = .w };
        pub const zwyx: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .y, .@"3" = .x };
        pub const zwyy: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .y, .@"3" = .y };
        pub const zwyz: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .y, .@"3" = .z };
        pub const zwyw: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .y, .@"3" = .w };
        pub const zwzx: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .z, .@"3" = .x };
        pub const zwzy: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .z, .@"3" = .y };
        pub const zwzz: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .z, .@"3" = .z };
        pub const zwzw: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .z, .@"3" = .w };
        pub const zwwx: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .w, .@"3" = .x };
        pub const zwwy: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .w, .@"3" = .y };
        pub const zwwz: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .w, .@"3" = .z };
        pub const zwww: Selector = .{ .@"0" = .z, .@"1" = .w, .@"2" = .w, .@"3" = .w };
        pub const wxxx: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .x, .@"3" = .x };
        pub const wxxy: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .x, .@"3" = .y };
        pub const wxxz: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .x, .@"3" = .z };
        pub const wxxw: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .x, .@"3" = .w };
        pub const wxyx: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .y, .@"3" = .x };
        pub const wxyy: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .y, .@"3" = .y };
        pub const wxyz: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .y, .@"3" = .z };
        pub const wxyw: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .y, .@"3" = .w };
        pub const wxzx: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .z, .@"3" = .x };
        pub const wxzy: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .z, .@"3" = .y };
        pub const wxzz: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .z, .@"3" = .z };
        pub const wxzw: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .z, .@"3" = .w };
        pub const wxwx: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .w, .@"3" = .x };
        pub const wxwy: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .w, .@"3" = .y };
        pub const wxwz: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .w, .@"3" = .z };
        pub const wxww: Selector = .{ .@"0" = .w, .@"1" = .x, .@"2" = .w, .@"3" = .w };
        pub const wyxx: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .x, .@"3" = .x };
        pub const wyxy: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .x, .@"3" = .y };
        pub const wyxz: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .x, .@"3" = .z };
        pub const wyxw: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .x, .@"3" = .w };
        pub const wyyx: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .y, .@"3" = .x };
        pub const wyyy: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .y, .@"3" = .y };
        pub const wyyz: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .y, .@"3" = .z };
        pub const wyyw: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .y, .@"3" = .w };
        pub const wyzx: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .z, .@"3" = .x };
        pub const wyzy: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .z, .@"3" = .y };
        pub const wyzz: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .z, .@"3" = .z };
        pub const wyzw: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .z, .@"3" = .w };
        pub const wywx: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .w, .@"3" = .x };
        pub const wywy: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .w, .@"3" = .y };
        pub const wywz: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .w, .@"3" = .z };
        pub const wyww: Selector = .{ .@"0" = .w, .@"1" = .y, .@"2" = .w, .@"3" = .w };
        pub const wzxx: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .x, .@"3" = .x };
        pub const wzxy: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .x, .@"3" = .y };
        pub const wzxz: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .x, .@"3" = .z };
        pub const wzxw: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .x, .@"3" = .w };
        pub const wzyx: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .y, .@"3" = .x };
        pub const wzyy: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .y, .@"3" = .y };
        pub const wzyz: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .y, .@"3" = .z };
        pub const wzyw: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .y, .@"3" = .w };
        pub const wzzx: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .z, .@"3" = .x };
        pub const wzzy: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .z, .@"3" = .y };
        pub const wzzz: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .z, .@"3" = .z };
        pub const wzzw: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .z, .@"3" = .w };
        pub const wzwx: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .w, .@"3" = .x };
        pub const wzwy: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .w, .@"3" = .y };
        pub const wzwz: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .w, .@"3" = .z };
        pub const wzww: Selector = .{ .@"0" = .w, .@"1" = .z, .@"2" = .w, .@"3" = .w };
        pub const wwxx: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .x, .@"3" = .x };
        pub const wwxy: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .x, .@"3" = .y };
        pub const wwxz: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .x, .@"3" = .z };
        pub const wwxw: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .x, .@"3" = .w };
        pub const wwyx: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .y, .@"3" = .x };
        pub const wwyy: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .y, .@"3" = .y };
        pub const wwyz: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .y, .@"3" = .z };
        pub const wwyw: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .y, .@"3" = .w };
        pub const wwzx: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .z, .@"3" = .x };
        pub const wwzy: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .z, .@"3" = .y };
        pub const wwzz: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .z, .@"3" = .z };
        pub const wwzw: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .z, .@"3" = .w };
        pub const wwwx: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .w, .@"3" = .x };
        pub const wwwy: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .w, .@"3" = .y };
        pub const wwwz: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .w, .@"3" = .z };
        pub const wwww: Selector = .{ .@"0" = .w, .@"1" = .w, .@"2" = .w, .@"3" = .w };

        @"3": Component = .x,
        @"2": Component = .x,
        @"1": Component = .x,
        @"0": Component = .x,

        pub const ParseError = error{
            Syntax,
            InvalidComponent,
        };

        pub fn parse(value: []const u8) ParseError!Selector {
            if(value.len == 0 or value.len > 4) {
                return error.Syntax;
            }

            var selector: Selector = undefined;
            inline for ("0123", 0..) |f, i| {
                const component: Component = if(i >= value.len)
                    .x
                else 
                    @enumFromInt(std.mem.indexOf(u8, span, &.{value[i]}) orelse return error.InvalidComponent);

                @field(selector, std.mem.asBytes(&f)) = component;
            }

            return selector;
        }

        test parse {
            try testing.expectEqual(Selector.wxyz, try parse("wxyz"));
            try testing.expectEqual(Selector.wwww, try parse("wwww"));
            try testing.expectEqual(Selector.wxwx, try parse("wxwx"));
            try testing.expectEqual(Selector.xyzw, try parse("xyzw"));
            try testing.expectEqual(Selector.w, try parse("w"));
            try testing.expectEqual(Selector.yw, try parse("yw"));
            try testing.expectEqual(Selector.yzw, try parse("yzw"));
            try testing.expectError(error.InvalidComponent, parse("tzp"));
        }
    };
};

pub const OperandDescriptor = packed struct(u32) {
    destination_mask: Component.Mask,
    src1_neg: bool,
    src1_selector: Component.Selector,
    src2_neg: bool,
    src2_selector: Component.Selector,
    src3_neg: bool,
    src3_selector: Component.Selector,
    _unused0: u1 = 0,
};

pub const ComparisonOperation = enum(u3) {
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    true0,
    true1
};

pub const Condition = enum(u2) {
    @"or",
    @"and",
    x,
    y,
};

pub const Instruction = union(Format) {
    pub const Opcode = enum(u6) {
        pub const Mad = enum(u3) { _ };
        pub const Comparison = enum(u5) { _ };

        add,
        dp3,
        dp4,
        dph,
        dst,
        ex2,
        lg2,
        litp,
        mul,
        sge,
        slt,
        flr,
        max,
        min,
        rcp,
        rsq,

        mova = 0x12,
        mov,

        dphi = 0x18,
        dsti,
        sgei,
        slti,

        @"break" = 0x20,
        nop,
        end,
        breakc,
        call,
        callc,
        callu,
        ifu,
        ifc,
        loop,
        emit,
        setemit,
        jmpc,
        jmpu,
        cmp = 0x2E, // - 0x2F
        madi = 0x30, // - 0x37
        mad = 0x38, // - 0x3F
        _,

        pub fn toComparison(opcode: Opcode) ?Comparison {
            return switch (@intFromEnum(opcode)) {
                0x2E...0x2F => @enumFromInt(@intFromEnum(Opcode.cmp) >> 3),
                else => null,
            };
        }

        pub fn toMad(opcode: Opcode) ?Mad {
            return switch (@intFromEnum(opcode)) {
                0x30...0x37 => @enumFromInt(@intFromEnum(Opcode.madi) >> 3),
                0x38...0x3F => @enumFromInt(@intFromEnum(Opcode.mad) >> 3),
                else => null,
            };
        }
    };

    pub const format = struct {
        pub const Unparametized = packed struct(u32) { _unused0: u26, opcode: u6 };

        pub fn Register(comptime inverted: bool) type {
            return packed struct(u32) {
                operand_descriptor_id: u7,
                src2: (if (inverted) SourceRegister else SourceRegister.Limited),
                src1: (if (inverted) SourceRegister.Limited else SourceRegister),
                address_index: RelativeComponent,
                dst: DestinationRegister,
                opcode: Opcode,
            };
        }

        pub const Comparison = packed struct(u32) {
            operand_descriptor_id: u7,
            src2: SourceRegister.Limited,
            src1: SourceRegister,
            address_index: RelativeComponent,
            x_operation: ComparisonOperation,
            y_operation: ComparisonOperation,
            opcode: Opcode.Comparison,
        };

        pub const ControlFlow = packed struct(u32) {
            num: u8,
            _unused: u2 = 0,
            dst_word_offset: u12,
            condition: Condition,
            ref_y: bool,
            ref_x: bool,
            opcode: Opcode,
        };

        pub const ConstantControlFlow = packed struct(u32) {
            num: u8,
            _unused0: u2 = 0,
            dst_word_offset: u12,
            constant_id: IntegralRegister,
            opcode: Opcode,
        };

        pub const SetEmit = packed struct(u32) {
            _unused: u22,
            winding: bool,
            primitive_emit: bool,
            vertex_id: u2,
            opcode: Opcode,
        };

        pub fn Mad(comptime inverted: bool) type {
            return packed struct(u32) {
                operand_descriptor_id: u5,
                src3: (if (inverted) SourceRegister else SourceRegister.Limited),
                src2: (if (inverted) SourceRegister.Limited else SourceRegister),
                src1: SourceRegister.Limited,
                address_index: RelativeComponent,
                dst: DestinationRegister,
                opcode: Opcode.Mad,
            };
        }
    };

    pub const Format = enum {
        unparametized,
        register,
        register_inverted,
        register_unary,
        comparison,
        control_flow,
        constant_control_flow,
        set_emit,
        mad,
        mad_inverted,

        pub fn descriptorSize(fmt: Format) ?usize {
            return switch (fmt) {
                .unparametized, .control_flow, .constant_control_flow, .set_emit => null,
                .mad, .mad_inverted => 5,
                else => 7
            };
        }
    };

    unparametized: format.Unparametized,
    register: format.Register(false),
    register_inverted: format.Register(true),
    register_unary: format.Register(false),
    comparison: format.Comparison,
    control_flow: format.ControlFlow,
    constant_control_flow: format.ConstantControlFlow,
    set_emit: format.SetEmit,
    mad: format.Mad(false),
    mad_inverted: format.Mad(true),

    pub inline fn raw(in: Instruction) u32 {
        return switch (in) {
            inline else => |v| @bitCast(v),
        };
    }
};

const std = @import("std");
const testing = std.testing;
const register = @import("register.zig");

const RelativeComponent = register.RelativeComponent;
const SourceRegister = register.SourceRegister;
const DestinationRegister = register.DestinationRegister;
const IntegralRegister = register.IntegralRegister;
