//! PICA200 instruction encodings

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

        enable_w: bool = false,
        enable_z: bool = false,
        enable_y: bool = false,
        enable_x: bool = false,

        pub fn copyWith(mask: Mask, i: u2, value: bool) Mask {
            const bit_mask = @as(u4, 0b1000) >> i;
            const bit = (@as(u4, @intFromBool(value)) << 3) >> i;

            return @bitCast((@as(u4, @bitCast(mask)) & ~bit_mask) | bit);
        }

        pub fn size(mask: Mask) usize {
            return (((@as(usize, @intFromBool(mask.enable_x)) + @intFromBool(mask.enable_y)) + @intFromBool(mask.enable_z)) + @intFromBool(mask.enable_w));
        }

        pub const ParseError = error{
            Syntax,
            InvalidMask,
            InvalidComponent,
        };

        pub fn format(mask: Mask, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const enabled: []const bool = &.{ mask.enable_x, mask.enable_y, mask.enable_z, mask.enable_w };

            for (enabled, span) |e, c| if (e) {
                try writer.writeByte(c);
            };
        }

        pub fn parse(expression: []const u8) ParseError!Mask {
            if (expression.len == 0 or expression.len > 4) {
                return error.Syntax;
            }

            var last: ?usize = null;
            var mask: u4 = 0;
            for (expression) |c| {
                const component = std.mem.indexOf(u8, span, &.{c}) orelse return error.InvalidComponent;

                if (last) |l| {
                    if (component <= l) {
                        return error.InvalidMask;
                    }
                }

                mask |= @as(u4, 1) << @intCast(span.len - 1 - component);
                last = component;
            }

            return @bitCast(mask);
        }

        test parse {
            try testing.expect(Mask.xyzw == try parse("xyzw"));
            try testing.expect(Mask.w == try parse("w"));
            try testing.expect(Mask.yw == try parse("yw"));
            try testing.expect(Mask.yzw == try parse("yzw"));
            try testing.expect(error.InvalidMask == parse("zyx"));
            try testing.expect(error.InvalidMask == parse("wy"));
            try testing.expect(error.InvalidMask == parse("xxxx"));
            try testing.expect(error.InvalidMask == parse("wyxz"));
        }
    };

    pub const Selector = packed struct(u8) {
        pub const x: Selector = .xxxx;
        pub const y: Selector = .yyyy;
        pub const z: Selector = .zzzz;
        pub const w: Selector = .wwww;
        pub const xx: Selector = .xxxx;
        pub const xy: Selector = .xyyy;
        pub const xz: Selector = .xzzz;
        pub const xw: Selector = .xwww;
        pub const yx: Selector = .yxxx;
        pub const yy: Selector = .yyyy;
        pub const yz: Selector = .yzzz;
        pub const yw: Selector = .ywww;
        pub const zx: Selector = .zxxx;
        pub const zy: Selector = .zyyy;
        pub const zz: Selector = .zzzz;
        pub const zw: Selector = .zwww;
        pub const wx: Selector = .wxxx;
        pub const wy: Selector = .wyyy;
        pub const wz: Selector = .wzzz;
        pub const ww: Selector = .wwww;
        pub const xxx: Selector = .xxxx;
        pub const xxy: Selector = .xxyy;
        pub const xxz: Selector = .xxzz;
        pub const xxw: Selector = .xxww;
        pub const xyx: Selector = .xyxx;
        pub const xyy: Selector = .xyyy;
        pub const xyz: Selector = .xyzz;
        pub const xyw: Selector = .xyww;
        pub const xzx: Selector = .xzxx;
        pub const xzy: Selector = .xzyy;
        pub const xzz: Selector = .xzzz;
        pub const xzw: Selector = .xzww;
        pub const xwx: Selector = .xwxx;
        pub const xwy: Selector = .xwyy;
        pub const xwz: Selector = .xwzz;
        pub const xww: Selector = .xwww;
        pub const yxx: Selector = .yxxx;
        pub const yxy: Selector = .yxyy;
        pub const yxz: Selector = .yxzz;
        pub const yxw: Selector = .yxww;
        pub const yyx: Selector = .yyxx;
        pub const yyy: Selector = .yyyy;
        pub const yyz: Selector = .yyzz;
        pub const yyw: Selector = .yyww;
        pub const yzx: Selector = .yzxx;
        pub const yzy: Selector = .yzyy;
        pub const yzz: Selector = .yzzz;
        pub const yzw: Selector = .yzww;
        pub const ywx: Selector = .ywxx;
        pub const ywy: Selector = .ywyy;
        pub const ywz: Selector = .ywzz;
        pub const yww: Selector = .ywww;
        pub const zxx: Selector = .zxxx;
        pub const zxy: Selector = .zxyy;
        pub const zxz: Selector = .zxzz;
        pub const zxw: Selector = .zxww;
        pub const zyx: Selector = .zyxx;
        pub const zyy: Selector = .zyyy;
        pub const zyz: Selector = .zyzz;
        pub const zyw: Selector = .zyww;
        pub const zzx: Selector = .zzxx;
        pub const zzy: Selector = .zzyy;
        pub const zzz: Selector = .zzzz;
        pub const zzw: Selector = .zzww;
        pub const zwx: Selector = .zwxx;
        pub const zwy: Selector = .zwyy;
        pub const zwz: Selector = .zwzz;
        pub const zww: Selector = .zwww;
        pub const wxx: Selector = .wxxx;
        pub const wxy: Selector = .wxyy;
        pub const wxz: Selector = .wxzz;
        pub const wxw: Selector = .wxww;
        pub const wyx: Selector = .wyxx;
        pub const wyy: Selector = .wyyy;
        pub const wyz: Selector = .wyzz;
        pub const wyw: Selector = .wyww;
        pub const wzx: Selector = .wzxx;
        pub const wzy: Selector = .wzyy;
        pub const wzz: Selector = .wzzz;
        pub const wzw: Selector = .wzww;
        pub const wwx: Selector = .wwxx;
        pub const wwy: Selector = .wwyy;
        pub const wwz: Selector = .wwzz;
        pub const www: Selector = .wwww;
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

        @"3": Component,
        @"2": Component,
        @"1": Component,
        @"0": Component,

        const indexes = "0123";

        pub fn swizzle(selector: Selector, other: Selector) Selector {
            var new_selector: Selector = undefined;
            inline for (indexes) |f| {
                const component = @field(other, std.mem.asBytes(&f));

                @field(new_selector, std.mem.asBytes(&f)) = switch (component) {
                    inline else => |v| @field(selector, std.mem.asBytes(&indexes[@intFromEnum(v)])),
                };
            }
            return new_selector;
        }

        pub fn format(selector: Selector, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{t}{t}{t}{t}", .{ selector.@"0", selector.@"1", selector.@"2", selector.@"3" });
        }

        pub const ParseError = error{
            Syntax,
            InvalidComponent,
        };

        pub fn parse(expression: []const u8) ParseError!Selector {
            if (expression.len == 0 or expression.len > 4) {
                return error.Syntax;
            }

            var last: Component = undefined;
            var selector: Selector = undefined;
            inline for ("0123", 0..) |f, i| {
                const component: Component = if (i >= expression.len)
                    last
                else
                    @enumFromInt(std.mem.indexOf(u8, span, &.{expression[i]}) orelse return error.InvalidComponent);

                @field(selector, std.mem.asBytes(&f)) = component;
                last = component;
            }

            return selector;
        }

        /// parses sequential swizzles with '.' as a separator, returns the final swizzle
        pub fn parseSequential(expression: []const u8) ParseError!Selector {
            var swizzles = std.mem.tokenizeScalar(u8, expression, '.');

            var final_swizzle: Component.Selector = .xyzw;
            while (swizzles.next()) |swizzle_str| {
                const current_swizzle = try Component.Selector.parse(std.mem.trim(u8, swizzle_str, " \t"));
                final_swizzle = final_swizzle.swizzle(current_swizzle);
            }

            return final_swizzle;
        }

        test parse {
            try testing.expect(Selector.wwww == Selector.xyzw.swizzle(.wwww));
            try testing.expect(Selector.yzww == Selector.xyzw.swizzle(.wzyx).swizzle(.zyxx));
            try testing.expect(Selector.xyxy == Selector.xyzw.swizzle(.xxyy).swizzle(.xzyw));
            try testing.expect(Selector.wzyy == Selector.xyzw.swizzle(.wzyx).swizzle(.xyzz));

            try testing.expect(Selector.wxyz == try parse("wxyz"));
            try testing.expect(Selector.wwww == try parse("wwww"));
            try testing.expect(Selector.wxwx == try parse("wxwx"));
            try testing.expect(Selector.xyzw == try parse("xyzw"));
            try testing.expect(Selector.w == try parse("w"));
            try testing.expect(Selector.yw == try parse("yw"));
            try testing.expect(Selector.yzw == try parse("yzw"));
            try testing.expect(error.InvalidComponent == parse("tzp"));
        }
    };
};

pub const OperandDescriptor = packed struct(u32) {
    pub const Negation = enum(u1) {
        @"+",
        @"-",

        pub fn negate(neg: Negation) Negation {
            return switch (neg) {
                .@"+" => .@"-",
                .@"-" => .@"+",
            };
        }

        pub fn format(neg: Negation, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            return switch (neg) {
                .@"+" => {},
                .@"-" => try writer.writeByte('-'),
            };
        }
    };

    pub const Mask = packed struct(u8) {
        pub const unary: Mask = .{ .dst = true, .src1 = true };
        pub const binary: Mask = .{ .dst = true, .src1 = true, .src2 = true };
        pub const full: Mask = .{ .dst = true, .src1 = true, .src2 = true, .src3 = true };
        pub const comparison: Mask = .{ .src1 = true, .src2 = true };

        dst: bool = false,
        src1: bool = false,
        src2: bool = false,
        src3: bool = false,
        _: u4 = 0,

        pub fn contains(mask: Mask, other: Mask) bool {
            return @as(u8, @bitCast(mask)) <= @as(u8, @bitCast(other));
        }
    };

    dst_mask: Component.Mask = .xyzw,
    src1_neg: Negation = .@"+",
    src1_selector: Component.Selector = .xyzw,
    src2_neg: Negation = .@"+",
    src2_selector: Component.Selector = .xyzw,
    src3_neg: Negation = .@"+",
    src3_selector: Component.Selector = .xyzw,
    _unused0: u1 = 0,

    pub fn equalsMasked(desc: OperandDescriptor, mask: Mask, other: OperandDescriptor) bool {
        // zig fmt: off
        return (!mask.dst  or (desc.dst_mask == other.dst_mask))
           and (!mask.src1 or (desc.src1_neg == other.src1_neg and desc.src1_selector == other.src1_selector))
           and (!mask.src2 or (desc.src2_neg == other.src2_neg and desc.src2_selector == other.src2_selector))
           and (!mask.src3 or (desc.src3_neg == other.src3_neg and desc.src3_selector == other.src3_selector));
        // zig fmt: on
    }
};

pub const ComparisonOperation = enum(u3) {
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    true_0,
    true_1,

    pub fn invert(op: ComparisonOperation) ComparisonOperation {
        return switch (op) {
            .lt => .ge,
            .le => .gt,
            .ge => .lt,
            .gt => .le,
            else => op,
        };
    }
};

pub const Condition = enum(u2) { @"or", @"and", x, y };
pub const Primitive = enum(u1) { vertex, primitive };
pub const Winding = enum(u1) { default, invert };

pub const Instruction = packed union {
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
        cmp0 = 0x2E,
        cmp1 = 0x2F,
        madi0 = 0x30,
        madi1 = 0x31,
        madi2 = 0x32,
        madi3 = 0x33,
        madi4 = 0x34,
        madi5 = 0x35,
        madi6 = 0x36,
        madi7 = 0x37,
        mad0 = 0x38,
        mad1 = 0x39,
        mad2 = 0x3A,
        mad3 = 0x3B,
        mad4 = 0x3C,
        mad5 = 0x3D,
        mad6 = 0x3E,
        mad7 = 0x3F,
        _,

        pub fn isCommutative(opcode: Opcode) bool {
            return switch (opcode) {
                .add, .dp3, .dp4, .mul, .max, .min => true,
                else => false,
            };
        }

        pub fn invert(opcode: Opcode) ?Opcode {
            return switch (opcode) {
                .dph => .dphi,
                .dst => .dsti,
                .sge => .sgei,
                .slt => .slti,
                else => null,
            };
        }

        pub fn toComparison(opcode: Opcode) ?Comparison {
            return switch (@intFromEnum(opcode)) {
                @intFromEnum(Opcode.cmp0)...@intFromEnum(Opcode.cmp1) => @enumFromInt(@intFromEnum(Opcode.cmp0) >> 1),
                else => null,
            };
        }

        pub fn toMad(opcode: Opcode) ?Mad {
            return switch (@intFromEnum(opcode)) {
                0x30...0x37 => @enumFromInt(@intFromEnum(Opcode.madi0) >> 3),
                0x38...0x3F => @enumFromInt(@intFromEnum(Opcode.mad0) >> 3),
                else => null,
            };
        }
    };

    pub const format = struct {
        pub const Unparametized = packed struct(u32) { _unused0: u26 = 0, opcode: Opcode };

        pub fn Register(comptime inverted: bool) type {
            return packed struct(u32) {
                operand_descriptor_id: u7,
                src2: (if (inverted) SourceRegister else SourceRegister.Limited) = .v0,
                src1: (if (inverted) SourceRegister.Limited else SourceRegister),
                address_component: AddressComponent = .none,
                dst: DestinationRegister,
                opcode: Opcode,
            };
        }

        pub const Comparison = packed struct(u32) {
            operand_descriptor_id: u7,
            src2: SourceRegister.Limited,
            src1: SourceRegister,
            address_component: AddressComponent = .none,
            x_operation: ComparisonOperation,
            y_operation: ComparisonOperation,
            opcode: Opcode.Comparison,
        };

        pub const ControlFlow = packed struct(u32) {
            num: u8,
            _unused0: u2 = 0,
            dst: u12,
            condition: Condition,
            ref_y: bool,
            ref_x: bool,
            opcode: Opcode,
        };

        pub const ConstantControlFlow = packed struct(u32) {
            num: u8,
            _unused0: u2 = 0,
            dst: u12,
            src: IntegralRegister,
            opcode: Opcode,
        };

        pub const SetEmit = packed struct(u32) {
            _unused0: u22 = 0,
            winding: Winding,
            primitive_emit: Primitive,
            vertex_id: u2,
            opcode: Opcode,
        };

        pub fn Mad(comptime inverted: bool) type {
            return packed struct(u32) {
                operand_descriptor_id: u5,
                src3: (if (inverted) SourceRegister else SourceRegister.Limited),
                src2: (if (inverted) SourceRegister.Limited else SourceRegister),
                src1: SourceRegister.Limited,
                address_component: AddressComponent,
                dst: DestinationRegister,
                opcode: Opcode.Mad,
            };
        }
    };

    unparametized: format.Unparametized,
    register: format.Register(false),
    register_inverted: format.Register(true),
    comparison: format.Comparison,
    control_flow: format.ControlFlow,
    constant_control_flow: format.ConstantControlFlow,
    set_emit: format.SetEmit,
    mad: format.Mad(false),
    mad_inverted: format.Mad(true),

    pub fn fmtDisassemble(inst: Instruction, descriptors: []const OperandDescriptor) Format {
        return .{ .inst = inst, .descriptors = descriptors };
    }

    pub const Format = struct {
        inst: Instruction,
        descriptors: []const OperandDescriptor,

        pub fn format(fmt: Format, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const inst = fmt.inst;
            const descriptors = fmt.descriptors;

            return switch (@intFromEnum(inst.unparametized.opcode)) {
                @intFromEnum(Opcode.@"break"),
                @intFromEnum(Opcode.nop),
                @intFromEnum(Opcode.end),
                @intFromEnum(Opcode.emit),
                => try writer.print("{t}", .{inst.unparametized.opcode}),
                @intFromEnum(Opcode.add),
                @intFromEnum(Opcode.dp3),
                @intFromEnum(Opcode.dp4),
                @intFromEnum(Opcode.dph),
                @intFromEnum(Opcode.dst),
                @intFromEnum(Opcode.mul),
                @intFromEnum(Opcode.sge),
                @intFromEnum(Opcode.slt),
                @intFromEnum(Opcode.max),
                @intFromEnum(Opcode.min),
                => {
                    const binary = inst.register;

                    if (binary.operand_descriptor_id < descriptors.len) {
                        const desc = descriptors[binary.operand_descriptor_id];

                        try writer.print("{t} {t}.{f}, {f}{t}{f}.{f}, {f}{t}.{f}", .{ binary.opcode, binary.dst, desc.dst_mask, desc.src1_neg, binary.src1, binary.address_component, desc.src1_selector, desc.src2_neg, binary.src2, desc.src2_selector });
                    } else try writer.print("{t} {t}.????, ?{t}{f}.????, ?{t}.????", .{ binary.opcode, binary.dst, binary.src1, binary.address_component, binary.src2 });
                },
                @intFromEnum(Opcode.dphi),
                @intFromEnum(Opcode.dsti),
                @intFromEnum(Opcode.sgei),
                @intFromEnum(Opcode.slti),
                => {
                    const binary = inst.register;

                    if (binary.operand_descriptor_id < descriptors.len) {
                        const desc = descriptors[binary.operand_descriptor_id];

                        // NOTE: @tagName because we want to remove the `i` suffix.
                        try writer.print("{s} {t}.{f}, {f}{t}.{f}, {f}{t}{f}.{f}", .{ @tagName(binary.opcode)[0..3], binary.dst, desc.dst_mask, desc.src1_neg, binary.src1, desc.src1_selector, desc.src2_neg, binary.src2, binary.address_component, desc.src2_selector });
                    } else try writer.print("{s} {t}.????, ?{t}.????, ?{t}{f}.????", .{ @tagName(binary.opcode)[0..3], binary.dst, binary.src1, binary.src2, binary.address_component });
                },
                @intFromEnum(Opcode.ex2),
                @intFromEnum(Opcode.lg2),
                @intFromEnum(Opcode.litp),
                @intFromEnum(Opcode.flr),
                @intFromEnum(Opcode.rcp),
                @intFromEnum(Opcode.rsq),
                @intFromEnum(Opcode.mova),
                @intFromEnum(Opcode.mov),
                => {
                    const unary = inst.register;

                    if (unary.operand_descriptor_id < descriptors.len) {
                        const desc = descriptors[unary.operand_descriptor_id];

                        try writer.print("{t} {t}.{f}, {f}{t}{f}.{f}", .{ unary.opcode, unary.dst, desc.dst_mask, desc.src1_neg, unary.src1, unary.address_component, desc.src1_selector });
                    } else try writer.print("{t} {t}.????, ?{t}{f}.????", .{ unary.opcode, unary.dst, unary.src1, unary.address_component });
                },
                @intFromEnum(Opcode.breakc),
                => try writer.print("breakc {t}, {}, {}", .{ inst.control_flow.condition, inst.control_flow.ref_x, inst.control_flow.ref_y }),
                @intFromEnum(Opcode.jmpc),
                => try writer.print("jmpc {t}, {}, {}, L_{X:0>3}", .{ inst.control_flow.condition, inst.control_flow.ref_x, inst.control_flow.ref_y, inst.control_flow.dst }),
                @intFromEnum(Opcode.call),
                => try writer.print("call L_{X:0>3}, L_{X:0>3}", .{ inst.control_flow.dst, inst.control_flow.dst + inst.control_flow.num }),
                @intFromEnum(Opcode.callc),
                @intFromEnum(Opcode.ifc),
                => try writer.print("{t} {t}, {}, {}, L_{X:0>3}, L_{X:0>3}", .{ inst.control_flow.opcode, inst.control_flow.condition, inst.control_flow.ref_x, inst.control_flow.ref_y, inst.control_flow.dst, inst.control_flow.dst + inst.control_flow.num }),
                @intFromEnum(Opcode.callu),
                @intFromEnum(Opcode.ifu),
                => try writer.print("{t} {t}, L_{X:0>3}, L_{X:0>3}", .{ inst.constant_control_flow.opcode, inst.constant_control_flow.src.bool, inst.constant_control_flow.dst, inst.constant_control_flow.dst + inst.constant_control_flow.num }),
                @intFromEnum(Opcode.jmpu),
                => try writer.print("jmpu {t}, {}, L_{X:0>3}", .{ inst.constant_control_flow.src.bool, inst.constant_control_flow.num == 0, inst.constant_control_flow.dst }),
                @intFromEnum(Opcode.loop),
                => try writer.print("loop {t}, L_{X:0>3}", .{ inst.constant_control_flow.src.int.used, inst.constant_control_flow.dst + @sizeOf(Instruction) }),
                @intFromEnum(Opcode.setemit),
                => try writer.print("setemit {}, {t}, {t}", .{ inst.set_emit.vertex_id, inst.set_emit.primitive_emit, inst.set_emit.winding }),
                @intFromEnum(Opcode.cmp0),
                @intFromEnum(Opcode.cmp1),
                => {
                    const cmp = inst.comparison;

                    if (cmp.operand_descriptor_id < descriptors.len) {
                        const desc = descriptors[cmp.operand_descriptor_id];

                        try writer.print("cmp {f}{t}{f}.{f}, {t}, {t}, {f}{t}.{f}", .{ desc.src1_neg, cmp.src1, cmp.address_component, desc.src1_selector, cmp.x_operation, cmp.y_operation, desc.src2_neg, cmp.src2, desc.src2_selector });
                    } else try writer.print("cmp ?{t}{f}.????, {t}, {t}, ?{t}.????", .{ cmp.src1, cmp.address_component, cmp.x_operation, cmp.y_operation, cmp.src2 });
                },
                @intFromEnum(Opcode.mad0)...@intFromEnum(Opcode.mad7) => {
                    const mad = inst.mad;

                    if (mad.operand_descriptor_id < descriptors.len) {
                        const desc = descriptors[mad.operand_descriptor_id];

                        try writer.print("mad {t}.{f}, {f}{t}.{f}, {f}{t}{f}.{f}, {f}{t}.{f}", .{ mad.dst, desc.dst_mask, desc.src1_neg, mad.src1, desc.src1_selector, desc.src2_neg, mad.src2, mad.address_component, desc.src2_selector, desc.src3_neg, mad.src3, desc.src3_selector });
                    } else try writer.print("mad {t}.????, ?{t}.????, ?{t}{f}.????, ?{t}.????", .{ mad.dst, mad.src1, mad.src2, mad.address_component, mad.src3 });
                },
                @intFromEnum(Opcode.madi0)...@intFromEnum(Opcode.madi7) => {
                    const mad = inst.mad_inverted;

                    if (mad.operand_descriptor_id < descriptors.len) {
                        const desc = descriptors[mad.operand_descriptor_id];

                        try writer.print("mad {t}.{f}, {f}{t}.{f}, {f}{t}.{f}, {f}{t}{f}.{f}", .{ mad.dst, desc.dst_mask, desc.src1_neg, mad.src1, desc.src1_selector, desc.src2_neg, mad.src2, desc.src2_selector, desc.src3_neg, mad.src3, mad.address_component, desc.src3_selector });
                    } else try writer.print("mad {t}.????, ?{t}.????, ?{t}.????, ?{t}{f}.????", .{ mad.dst, mad.src1, mad.src2, mad.src3, mad.address_component });
                },
                else => try writer.print("??? (0x{X:0>8})", .{@as(u32, @bitCast(fmt.inst))}),
            };
        }
    };
};

const std = @import("std");
const testing = std.testing;

const zitrus = @import("zitrus");
const shader = zitrus.hardware.pica.shader;

const AddressComponent = shader.register.AddressComponent;
const SourceRegister = shader.register.Source;
const DestinationRegister = shader.register.Destination;
const IntegralRegister = shader.register.Integral;
