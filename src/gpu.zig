// Taken from / Credits:
// https://problemkaputt.de/gbatek.htm#3dsgpuinternalregisteroverview
// https://www.3dbrew.org/wiki/GPU/External_Registers
// https://www.3dbrew.org/wiki/GPU/Internal_Registers

pub const F3_12 = pica.F3_12;
pub const F7_12 = pica.F7_12;
pub const F7_16 = pica.F7_16;
pub const F7_23 = pica.F7_23;
pub const F7_16x4 = pica.F7_16x4;

pub const Screen = enum(u1) {
    top,
    bottom,

    pub inline fn width(_: Screen) usize {
        return 240;
    }

    pub inline fn height(screen: Screen) usize {
        return switch (screen) {
            .top => 400,
            .bottom => 320,
        };
    }
};

pub const Dimensions = packed struct(u32) { x: u16, y: u16 };
pub const SignedDimensions = packed struct(u32) { x: i16, y: i16 };

pub const PixelSize = enum(u2) {
    @"16",
    @"24",
    @"32",
    _,

    pub inline fn is24(fill: PixelSize) bool {
        return switch (fill) {
            1, 3 => true,
            else => false,
        };
    }
};

pub const ColorFormat = enum(u3) {
    pub const Rgba8 = extern struct { r: u8, g: u8, b: u8, a:u8 };
    pub const Abgr8 = extern struct { a: u8, b: u8, g: u8, r: u8 };
    pub const Bgr8 = extern struct { b: u8, g: u8, r: u8 };
    pub const Bgr565 = packed struct(u16) { b: u5, g: u6, r: u5 };
    pub const A1Bgr5 = packed struct(u16) { a: u1, b: u5, g: u5, r: u5 };
    pub const ABgr4 = packed struct(u16) { a: u4, b: u4, g: u4, r: u4 };

    abgr8,
    bgr8,
    bgr565,
    a1_bgr5,
    abgr4,

    pub inline fn Pixel(comptime format: ColorFormat) type {
        return switch (format) {
            .abgr8 => Abgr8,
            .bgr8 => Bgr8,
            .bgr565 => Bgr565,
            .a1_bgr5 => A1Bgr5,
            .abgr4 => ABgr4,
        };
    }

    pub inline fn pixelSize(format: ColorFormat) PixelSize {
        return switch (format.bytesPerPixel()) {
            2 => .@"16",
            3 => .@"24",
            4 => .@"32",
            else => unreachable,
        };
    }

    pub inline fn bytesPerPixel(format: ColorFormat) usize {
        return switch (format) {
            inline else => |f| @sizeOf(f.Pixel()),
        };
    }

    pub inline fn components(format: ColorFormat) usize {
        return switch (format) {
            inline else => |f| @typeInfo(f.Pixel()).@"struct".fields.len,
        };
    }
};

pub const DepthFormat = enum(u2) {
    @"16",
    @"24" = 2,
    @"24_depth_8_stencil",
};

pub const FramebufferInterlacingMode = enum(u2) {
    none,
    scanline_doubling,
    enable,
    enable_inverted,
};

pub const DmaSize = enum(u2) {
    @"32",
    @"64",
    @"128",
    vram,
};

pub const TopFramebufferMode = enum {
    @"2d",
    @"3d",
    full_resolution,
};

pub const FramebufferFormat = packed struct(u32) {
    color_format: ColorFormat,
    interlacing_mode: FramebufferInterlacingMode,
    alternative_pixel_output: bool,
    unknown0: u1 = 0,
    dma_size: DmaSize,
    unknown1: u7 = 0,
    unknown2: u16 = 0,

    pub inline fn mode(format: FramebufferFormat) TopFramebufferMode {
        return switch (format.interlacing_mode) {
            .enable => .@"3d",
            else => if (format.alternative_pixel_output) .@"2d" else .full_resolution,
        };
    }
};

pub const CullingMode = enum(u2) {
    none,
    front,
    back,
};

pub const ScissorMode = enum(u2) { disable, outside, inside };

pub const EarlyDepthFunction = enum(u2) {
    ge,
    gt,
    le,
    lt,
};

pub const OutputMap = packed struct(u32) {
    pub const Semantic = enum(u5) {
        position_x,
        position_y,
        position_z,
        position_w,

        normal_quaternion_x,
        normal_quaternion_y,
        normal_quaternion_z,
        normal_quaternion_w,

        color_r,
        color_g,
        color_b,
        color_a,

        texture_coordinate_0_u,
        texture_coordinate_0_v,
        texture_coordinate_1_u,
        texture_coordinate_1_v,
        texture_coordinate_0_w,

        view_x = 0x12,
        view_y,
        view_z,

        texture_coordinate_2_u,
        texture_coordinate_2_v,

        unused = 0x1F,
    };

    x: Semantic,
    _unusd0: u3 = 0,
    y: Semantic,
    _unusd1: u3 = 0,
    z: Semantic,
    _unusd2: u3 = 0,
    w: Semantic,
    _unusd3: u3 = 0,
};

pub const BlendEquation = enum(u3) {
    add,
    sub,
    reverse_sub,
    min,
    max,
};

pub const BlendFunction = enum(u4) {
    zero,
    one,
    src_color,
    one_minus_src_color,
    dst_color,
    one_minus_dst_color,
    src_alpha,
    one_minus_src_alpha,
    dst_alpha,
    one_minus_dst_alpha,
    constant_color,
    one_minus_constant_color,
    constant_alpha,
    one_minus_constant_alpha,
    src_alpha_saturate,
};

pub const LogicOperation = enum(u4) {
    clear,
    @"and",
    reverse_and,
    copy,
    set,
    inverted_copy,
    nop,
    invert,
    nand,
    @"or",
    nor,
    xor,
    equivalent,
    inverted_and,
    reverse_or,
    inverted_or,
};

pub const CompareFunction = enum(u3) {
    never,
    always,
    eq,
    neq,
    lt,
    le,
    gt,
    ge,
};

pub const StencilOperation = enum(u3) {
    keep,
    zero,
    replace,
    increment,
    decrement,
    invert,
    increment_wrap,
    decrement_wrap,
};

pub const PrimitiveMode = enum(u2) {
    triangle,
    triangle_strip,
    triangle_fan,
    geometry,
};

pub const AttributeFormat = packed struct(u4) {
    pub const Type = enum(u2) { i8, u8, i16, f32 };
    pub const Size = enum(u2) { x, xy, xyz, xyzw };

    type: Type = .i8,
    size: Size = .x,
};

pub const AttributeArrayComponent = enum(u4) {
    attribute_0,
    attribute_1,
    attribute_2,
    attribute_3,
    attribute_4,
    attribute_5,
    attribute_6,
    attribute_7,
    attribute_8,
    attribute_9,
    attribute_10,
    attribute_11,

    padding_4,
    padding_8,
    padding_12,
    padding_16,
};

pub const IndexFormat = enum(u1) { u8, u16 };

pub const ColorBufferFormat = enum(u3) { abgr8, a1_bgr5 = 2, bgr565, abgr4 };

// XXX: well, i suppose they'd be floats?
pub const DepthBufferFormat = enum(u2) { f16, f24 = 2, f24xi8 };

pub const TextureEnvironmentSource = enum(u4) {
    primary_color,
    fragment_primary_color,
    fragment_secondary_color,
    texture_0,
    texture_1,
    texture_2,
    texture_3,
    previous_buffer = 0xD,
    constant,
    previous,
};

pub const TextureEnvironmentRgbOperand = enum(u4) {
    source_color,
    one_minus_source_color,
    source_alpha,
    one_minus_source_alpha,
    source_red,
    one_minus_source_red,
    source_green = 8,
    one_minus_source_green,
    source_blue = 12,
    one_minus_source_blue,
};

pub const TextureEnvironmentAlphaOperand = enum(u3) {
    source_alpha,
    one_minus_source_alpha,
    source_red,
    one_minus_source_red,
    source_green,
    one_minus_source_green,
    source_blue,
    one_minus_source_blue,
};

pub const TextureEnvironmentCombiner = enum(u4) {
    replace,
    modulate,
    add,
    add_signed,
    interpolate,
    subtract,
    dot3_rgb,
    dot3_rgba,
    multiply_add,
    add_multiply,
};

pub const TextureEnvironmentFogMode = enum(u3) {
    disabled,
    fog = 5,
    gas = 7,
};

pub const TextureEnvironmentShadingDensity = enum(u1) {
    plain,
    depth,
};

// TODO: Properly finish this
pub const Registers = struct {
    pub const WrappedF7_23 = packed struct(u32) {
        _: u1 = 0,
        value: F7_23,

        pub fn fromFloat(value: F7_23) WrappedF7_23 {
            return .{ .value = value };
        }
    };

    pub const WrappedF7_16 = packed struct(u32) {
        value: F7_16,
        _: u8 = 0,

        pub fn fromFloat(value: F7_16) WrappedF7_16 {
            return .{ .value = value };
        }
    };

    pub const VRamPower = packed struct(u32) {
        _unknown0: u8,
        power_off_a_low: bool,
        power_off_a_high: bool,
        power_off_b_low: bool,
        power_off_b_high: bool,
        _unknown1: u20,
    };

    pub const InterruptFlags = packed struct(u32) {
        _unknown0: bool,
        _unknown1: bool,
        _unused0: u24 = 0,
        psc0: bool,
        psc1: bool,
        pdc0: bool,
        pdc1: bool,
        ppf: bool,
        p3d: bool,
    };

    pub const BusyFlags = packed struct(u32) {
        _unused0: u10,
        _unknown1: bool,
        _unused1: u6,
        _unknown_vram_power_0: bool,
        _unknown_vram_power_1: bool,
        memory_fill_busy: bool,
        memory_copy_busy: bool,
        _unused2: u11,
    };

    pub const TrafficStatus = extern struct {
        total_non_vram_reads: u32,
        total_non_vram_writes: u32,
        total_vram_a_reads: u32,
        total_vram_a_writes: u32,
        total_vram_b_reads: u32,
        total_vram_b_writes: u32,
        polygon_array_reads: u32,
        polygon_texture_reads: u32,
        polygon_depth_buffer_reads: u32,
        polygon_depth_buffer_writes: u32,
        polygon_color_buffer_reads: u32,
        polygon_color_buffer_writes: u32,
        lcd_upper_screen_reads: u32,
        lcd_lower_screen_reads: u32,
        memory_copy_src_reads: u32,
        memory_copy_dst_writes: u32,
        memory_fill_dst_writes: [2]u32,
        cpu_reads_from_vram_a_b: u32,
        cpu_writes_to_vram_a_b: u32,
    };

    // XXX: Proper field names and structures
    pub const Pdc = extern struct {
        pub const Timing = extern struct {
            total: u32,
            start: u32,
            border: u32,
            front_porch: u32,
            sync: u32,
            back_porch: u32,
            border_end: u32,
            interrupt: u32,
        };

        pub const Control = packed struct(u32) {
            enable: bool,
            _unused0: u7 = 0,
            disable_hblank_irq: bool,
            disable_vblank_irq: bool,
            disable_error_irq: bool,
            _unused1: u5 = 0,
            enable_output: bool,
            _unused2: u15 = 0,
        };

        horizontal: Timing,
        _unknown0: u32 = 0,

        vertical: Timing,
        _unknown1: u32 = 0,

        disable_sync: packed struct(u32) {
            horizontal: bool,
            _unwritable0: u7 = 0,
            vertical: bool,
            _unwritable1: u23 = 0,
        },
        border_color: packed struct(u32) {
            _unused: u8 = 0,
            r: u8,
            g: u8,
            b: u8,
        },
        hcount: u32,
        vcount: u32,
        _unknown2: u32 = 0,
        pixel_dimensions: Dimensions,
        horizontal_border: Dimensions,
        vertical_border: Dimensions,
        framebuffer_a_first: usize,
        framebuffer_a_second: usize,
        framebuffer_format: FramebufferFormat,
        control: Control,
        swap: packed struct(u32) {
            next: u1,
            _unused0: u3 = 0,
            displaying: bool,
            _unused1: u3 = 0,
            reset_fifo: bool,
            _unused2: u7 = 0,
            hblank_ack: bool,
            vblank_ack: bool,
            error_ack: bool,
            _unused3: u13 = 0,
        },
        _unknown3: u32 = 0,
        color_lookup_table: packed struct(u32) {
            index: u8,
            _unused: u24 = 0,
        },
        color_lookup_table_data: packed struct(u32) {
            _unused: u8 = 0,
            r: u8,
            g: u8,
            b: u8,
        },
        _unknown4: [2]u32 = @splat(0),
        framebuffer_stride: usize,
        framebuffer_b_first: usize,
        framebuffer_b_second: usize,
        _unknown5: u32 = 0,
        _unknown6: [24]u32 = @splat(0),
    };

    pub const MemoryFill = extern struct {
        pub const Control = packed struct(u16) {
            pub const none: Control = .{ .busy = false, .width = .@"16" };

            busy: bool,
            finished: bool = false,
            _unused0: u6 = 0,
            width: PixelSize,
            _unused1: u6 = 0,

            pub fn init(width: PixelSize) Control {
                return .{ .busy = true, .width = width };
            }
        };

        start: AlignedPhysicalAddress(.@"16", .@"8"),
        end: AlignedPhysicalAddress(.@"16", .@"8"),
        value: u32,
        control: Control,
        _padding0: u16 = 0,
    };

    pub const MemoryCopy = extern struct {
        pub const Flags = packed struct(u32) {
            pub const Downscale = enum(u2) { none, @"2x1", @"2x2" };

            flip_v: bool,
            linear_tiled: bool,
            output_width_less_than_input: bool,
            texture_copy_mode: bool,
            _unwritable0: u1 = 0,
            tiled_tiled: bool,
            _unwritable1: u2 = 0,
            input_format: ColorFormat,
            _unwritable2: u1 = 0,
            output_format: ColorFormat,
            _unwritable3: u1 = 0,
            use_32x32_tiles: bool,
            _unwritable4: u7 = 0,
            downscale: Downscale,
            _unwritable5: u6 = 0,
        };

        input: AlignedPhysicalAddress(.@"16", .@"8"),
        output: AlignedPhysicalAddress(.@"16", .@"8"),
        output_dimensions: Dimensions,
        input_dimensions: Dimensions,
        flags: Flags,
        write_0_before_display_transfer: u32,
        control: packed struct(u32) {
            start: bool,
            _unused0: u7 = 0,
            finished: bool,
            _unused1: u23 = 0,
        },
        _unknown0: u32 = 0,
        texture_size: usize,
        texture_src_dimensions: Dimensions,
        texture_dst_dimensions: Dimensions,
    };

    // FIXME: Remove usages of @Vector() in packed structs!
    pub const Internal = extern struct {
        pub const Trigger = packed struct(u32) {
            pub const trigger: Trigger = .{ .start = true };

            start: bool = false,
            _: u31 = 0,
        };

        pub const EnableBit = packed struct(u32) {
            pub const disable: EnableBit = .{ .enable_bit = false };
            pub const enable: EnableBit = .{ .enable_bit = true };

            enable_bit: bool = false,
            _: u31 = 0,
        };

        pub const DisableBit = packed struct(u32) {
            pub const disable: DisableBit = .{ .disable_bit = true };
            pub const enable: DisableBit = .{};

            disable_bit: bool = false,
            _: u31 = 0,
        };

        pub const Interrupt = extern struct {
            pub const Mask = packed struct(u64) { disabled: @Vector(64, bool) };
            pub const Stat = packed struct(u64) { match: @Vector(64, bool) };
            pub const AutoStop = packed struct(u32) {
                stop_command_list: bool,
                _unused0: u31 = 0,
            };

            ack: [64]u8,
            req: [64]u8,
            cmp: [64]u8,
            mask: Mask align(@alignOf(u32)),
            stat: Stat align(@alignOf(u32)),
            autostop: AutoStop,
            fixed_0x00010002: u32,
        };

        pub const Rasterizer = extern struct {
            pub const OutputAttributeMode = packed struct(u32) {
                use_texture_coordinates: bool = false,
                _: u31 = 0,
            };

            pub const OutputAttributeClock = packed struct(u32) {
                position_z_present: bool = false,
                color_present: bool = false,
                _unused0: u6 = 0,
                texture_coordinates_0_present: bool = false,
                texture_coordinates_1_present: bool = false,
                texture_coordinates_2_present: bool = false,
                _unknown0: u4 = 0,
                texture_coordinates_0_w_present: bool = false,
                _unknown1: u1 = 0,
                _unused1: u6 = 0,
                normal_quaternion_or_view_present: bool = false,
                _unused2: u8 = 0,
            };

            pub const FacecullingConfig = packed struct(u32) {
                mode: CullingMode,
                _: u30 = 0,
            };

            faceculling_config: FacecullingConfig,
            viewport_h_scale: WrappedF7_16,
            viewport_h_step: WrappedF7_23,
            viewport_v_scale: WrappedF7_16,
            viewport_v_step: WrappedF7_23,
            _unknown0: u32,
            _unknown1: u32,
            fragment_operation_clip: EnableBit,
            fragment_operation_clip_data: [4]WrappedF7_16,
            _unknown2: u32,
            depth_map_scale: WrappedF7_16,
            depth_map_offset: WrappedF7_16,
            shader_output_map_total: packed struct(u32) { num: u3, _: u29 = 0 },
            shader_output_map_output: [7]OutputMap,
            _unknown3: u32,
            _unknown4: u32,
            _unknown5: u32,
            status_num_vertices_received: u32,
            status_num_triangles_received: u32,
            status_num_triangles_displayed: u32,
            _unknown6: [3]u32,
            _unknown7: u32,
            early_depth_function: packed struct(u32) { function: EarlyDepthFunction, _: u30 = 0 },
            early_depth_test_1: EnableBit,
            early_depth_clear: Trigger,
            shader_output_attribute_mode: OutputAttributeMode,
            scissor_config: packed struct(u32) { mode: ScissorMode, _: u30 = 0 },
            scissor_start: Dimensions,
            scissor_end: Dimensions,
            viewport_xy: SignedDimensions,
            _unknown8: u32,
            early_depth_data: u32,
            _unknown9: u32,
            _unknown10: u32,
            depth_map_enable: EnableBit,
            /// Does not seem to have an effect but it's still documented like this
            _unused_render_buffer_dimensions: u32,
            shader_output_attribute_clock: OutputAttributeClock,
        };

        pub const Texturing = extern struct {
            pub const Main = extern struct {
                border_color: u32,
                dimensions: u32,
                param: u32,
                lod: u32,
                address: [6]u32,
                shadow: u32,
                _unknown0: u32,
                _unknown1: u32,
                type: u32,
            };

            pub const Sub = extern struct {
                border_color: u32,
                dimensions: u32,
                param: u32,
                lod: u32,
                addr: u32,
                type: u32,
            };

            config: u32,
            texture_0: Main,
            lighting_enable: EnableBit,
            _unknown0: u32,
            texture_1: Sub,
            _unknown1: [2]u32,
            texture_2: Sub,
        };

        pub const TexturingProcedural = extern struct {
            pub const Main = extern struct {
                procedural_texture: [5]u32,
                procedural_texture_5_low: u32,
                procedural_texture_5_high: u32,
            };

            texture_3: Main,
            lut_index: u32,
            lut_data: [8]u32,
        };

        pub const TexturingEnvironment = extern struct {
            pub const Main = extern struct {
                pub const Source = packed struct(u32) {
                    rgb_source_0: TextureEnvironmentSource,
                    rgb_source_1: TextureEnvironmentSource,
                    rgb_source_2: TextureEnvironmentSource,
                    _unused0: u4 = 0,
                    alpha_source_0: TextureEnvironmentSource,
                    alpha_source_1: TextureEnvironmentSource,
                    alpha_source_2: TextureEnvironmentSource,
                    _unused1: u4 = 0,
                };
                
                pub const Operand = packed struct(u32) {
                    rgb_operand_0: TextureEnvironmentRgbOperand,
                    rgb_operand_1: TextureEnvironmentRgbOperand,
                    rgb_operand_2: TextureEnvironmentRgbOperand,
                    alpha_operand_0: TextureEnvironmentAlphaOperand,
                    alpha_operand_1: TextureEnvironmentAlphaOperand,
                    alpha_operand_2: TextureEnvironmentAlphaOperand,
                    _unused0: u11 = 0,
                };

                pub const Combiner = packed struct(u32) {
                    rgb_combine: TextureEnvironmentCombiner,
                    _unused0: u12 = 0,
                    alpha_combine: TextureEnvironmentCombiner,
                    _unused1: u12 = 0,
                };

                source: Source,
                operand: Operand,
                combiner: Combiner,
                color: ColorFormat.Rgba8,
                scale: u32,
            };

            pub const UpdateBuffer = packed struct(u32) {
                pub const Previous = enum(u1) { previous_buffer, previous };

                fog_mode: TextureEnvironmentFogMode,
                shading_density_source: TextureEnvironmentShadingDensity,
                _unused0: u4 = 0,
                tex_env_1_rgb_buffer_input: Previous,
                tex_env_2_rgb_buffer_input: Previous,
                tex_env_3_rgb_buffer_input: Previous,
                tex_env_4_rgb_buffer_input: Previous,
                tex_env_1_alpha_buffer_input: Previous,
                tex_env_2_alpha_buffer_input: Previous,
                tex_env_3_alpha_buffer_input: Previous,
                tex_env_4_alpha_buffer_input: Previous,
                z_flip: bool,
                _unused1: u7 = 0,
                _unknown0: u2 = 0,
                _unused2: u6 = 0,
            };

            texture_environment_0: Main,
            _unknown0: [3]u32,
            texture_environment_1: Main,
            _unknown1: [3]u32,
            texture_environment_2: Main,
            _unknown2: [3]u32,
            texture_environment_3: Main,
            _unknown3: [3]u32,
            update_buffer: UpdateBuffer,
            fog_color: ColorFormat.Rgba8,
            _unknown4: u32,
            _unknown5: u32,
            gas_attenuation: u32,
            gas_accumulation_max: u32,
            fog_lut_index: u32,
            _unknown6: u32,
            fog_lut_data: [8]u32,
            texture_environment_4: Main,
            _unknown7: [3]u32,
            texture_environment_5: Main,
            buffer_color: ColorFormat.Rgba8,
        };

        pub const Framebuffer = extern struct {
            pub const ColorOperation = packed struct(u32) {
                pub const FragmentOperation = enum(u2) { default, gas, shadow = 3 };
                pub const BlendMode = enum(u1) { logic, blend };
                pub const RenderLines = enum(u1) { all, even };

                fragment_operation: FragmentOperation,
                _unused0: u6 = 0,

                mode: BlendMode,
                _unused1: u7 = 0,
                _unknown0: u8 = 0,
                render_lines: RenderLines = .all,
                render_nothing: bool = false,
                _unused2: u6 = 0,
            };

            pub const BlendConfig = packed struct(u32) {
                rgb_equation: BlendEquation,
                _unused0: u5 = 0,
                alpha_equation: BlendEquation,
                _unused1: u5 = 0,
                rgb_src_function: BlendFunction,
                rgb_dst_function: BlendFunction,
                alpha_src_function: BlendFunction,
                alpha_dst_function: BlendFunction,
            };

            pub const AlphaTestConfig = packed struct(u32) {
                enable: bool,
                _unused0: u3 = 0,
                function: CompareFunction,
                _unused1: u1 = 0,
                reference_value: u8,
                _unused3: u16 = 0,
            };

            pub const StencilTestConfig = packed struct(u32) {
                enable: bool,
                _unused0: u3 = 0,
                function: CompareFunction,
                _unused1: u1 = 0,
                src_mask: u8,
                value: i8,
                dst_mask: u8,
            };

            pub const StencilOperationConfig = packed struct(u32) {
                fail_operation: StencilOperation,
                _unused0: u1 = 0,
                z_fail_operation: StencilOperation,
                _unused1: u1 = 0,
                z_pass_operation: StencilOperation,
                _unused2: u21 = 0,
            };

            pub const DepthColorMaskConfig = packed struct(u32) {
                enable_depth_test: bool,
                _unused0: u3 = 0,
                depth_function: CompareFunction,
                r_write_enable: bool,
                g_write_enable: bool,
                b_write_enable: bool,
                a_write_enable: bool,
                depth_write_enable: bool,
                _unused1: u20 = 0,
            };

            pub const ColorRwMask = packed struct(u32) {
                pub const disable: ColorRwMask = .{};
                pub const enable: ColorRwMask = .{ .enable_all = 0xF };

                // NOTE: really weird that it doesn't trigger separate r g b a?
                enable_all: u4 = 0,
                _unused0: u28 = 0, 
            };

            pub const DepthStencilRwMask = packed struct(u32) {
                pub const disable: DepthStencilRwMask = .{};
                pub const enable: DepthStencilRwMask = .{ .depth_enable = true, .stencil_enable = true };

                stencil_enable: bool = false,
                depth_enable: bool = false,
                _unused0: u30 = 0,
            };
            
            pub const RenderBufferDimensions = packed struct(u32) {
                width: u11,
                _unused0: u1 = 0,
                height_end: u10,
                _unused1: u2 = 0,
                flip_vertically: bool = false,
                _unused2: u7 = 0,

                pub fn init(width: u11, height: u10, flip_vertically: bool) RenderBufferDimensions {
                    return .{ .width = width, .height_end = height - 1, .flip_vertically = flip_vertically };
                } 
            };

            pub const RenderBufferBlockSize = enum(u1) {
                @"8x8",
                @"32x32",
            };

            color_operation: ColorOperation,
            blend_config: BlendConfig,
            logic_operation: packed struct(u32) { operation: LogicOperation, _: u28 = 0 },
            blend_color: ColorFormat.Rgba8,
            fragment_operation_alpha_test: AlphaTestConfig,
            stencil_test: StencilTestConfig,
            stencil_operation: StencilOperationConfig,
            depth_color_mask: DepthColorMaskConfig,
            _unknown0: [5]u32,
            _unknown1: u32,
            _unknown2: u32,
            _unknown3: u32,
            render_buffer_invalidate: Trigger,
            render_buffer_flush: Trigger, 
            color_buffer_reading: ColorRwMask,
            color_buffer_writing: ColorRwMask,
            depth_buffer_reading: DepthStencilRwMask,
            depth_buffer_writing: DepthStencilRwMask,
            depth_buffer_format: packed struct(u32) {
                format: DepthBufferFormat,
                _unused0: u30 = 0,
            },
            color_buffer_format: packed struct(u32) {
                pixel_size: PixelSize,
                _unused0: u14 = 0,
                format: ColorBufferFormat,
                _unused1: u13 = 0,
            },
            early_depth_test_2: EnableBit,
            _unknown4: u32,
            _unknown5: u32,
            render_buffer_block_size: packed struct(u32) { mode: RenderBufferBlockSize, _: u31 = 0 },
            depth_buffer_location: AlignedPhysicalAddress(.@"64", .@"8"),
            color_buffer_location: AlignedPhysicalAddress(.@"64", .@"8"),
            render_buffer_dimensions: RenderBufferDimensions,
            _unknown6: u32,
            gas_light_xy: u32,
            gas_light_z: u32,
            gas_light_z_color: u32,
            gas_lut_index: u32,
            gas_lut_data: u32,
            _unknown7: u32,
            gas_delta_z_depth: u32,
            _unknown8: [9]u32,
            fragment_operation_shadow: u32,
            _unknown9: [14]u32,
            _unknown10: u32,
        };

        pub const FragmentLighting = extern struct {
            pub const Light = extern struct {
                specular: [2]u32,
                diffuse: u32,
                ambient: u32,
                vector_low: u32,
                vector_high: u32,
                spot_direction_low: u32,
                spot_direction_high: u32,
                _unknown0: u32,
                config: u32,
                attenuation_bias: u32,
                attenuation_scale: u32,
            };

            light: [8]Light,
            _unknown0: [32]u32,
            ambient: u32,
            num_lights: u32,
            config_0: u32,
            config_1: u32,
            lut_index: u32,
            disable: DisableBit,
            lut_data: [8]u32,
            lut_input_absolute: u32,
            lut_input_select: u32,
            lut_input_scale: u32,
            _unknown1: [30]u8,
            light_permutation: u32,
        };

        pub const GeometryPipeline = extern struct {
            pub const PrimitiveConfig = packed struct(u32) {
                total_vertex_outputs: u4,
                _unused0: u4 = 0,
                mode: PrimitiveMode,
                _unused1: u6 = 0,
                _unknown0: u1 = 0,
                _unused2: u15 = 0,
            };

            pub const AttributeBufferFormatLow = packed struct(u32) {
                attribute_0: AttributeFormat = .{},
                attribute_1: AttributeFormat = .{},
                attribute_2: AttributeFormat = .{},
                attribute_3: AttributeFormat = .{},
                attribute_4: AttributeFormat = .{},
                attribute_5: AttributeFormat = .{},
                attribute_6: AttributeFormat = .{},
                attribute_7: AttributeFormat = .{},
            };

            pub const AttributeBufferFormatHigh = packed struct(u32) {
                pub const Flags = enum(u1) { array, fixed };

                attribute_8: AttributeFormat = .{},
                attribute_9: AttributeFormat = .{},
                attribute_10: AttributeFormat = .{},
                attribute_11: AttributeFormat = .{},

                flags_0: Flags = .array,
                flags_1: Flags = .array,
                flags_2: Flags = .array,
                flags_3: Flags = .array,
                flags_4: Flags = .array,
                flags_5: Flags = .array,
                flags_6: Flags = .array,
                flags_7: Flags = .array,
                flags_8: Flags = .array,
                flags_9: Flags = .array,
                flags_10: Flags = .array,
                flags_11: Flags = .array,

                attributes_end: u4,
            };

            pub const AttributeBuffer = extern struct {
                pub const ConfigLow = packed struct(u32) {
                    component_0: AttributeArrayComponent = .attribute_0,
                    component_1: AttributeArrayComponent = .attribute_1,
                    component_2: AttributeArrayComponent = .attribute_2,
                    component_3: AttributeArrayComponent = .attribute_3,
                    component_4: AttributeArrayComponent = .attribute_4,
                    component_5: AttributeArrayComponent = .attribute_5,
                    component_6: AttributeArrayComponent = .attribute_6,
                    component_7: AttributeArrayComponent = .attribute_7,
                };

                pub const ConfigHigh = packed struct(u32) {
                    component_8: AttributeArrayComponent = .attribute_8,
                    component_9: AttributeArrayComponent = .attribute_9,
                    component_10: AttributeArrayComponent = .attribute_10,
                    component_11: AttributeArrayComponent = .attribute_11,

                    bytes_per_vertex: u8,
                    _unused0: u4 = 0,
                    num_components: u4,
                };

                offset: usize,
                config_low: ConfigLow,
                config_high: ConfigHigh,
            };

            pub const AttributeIndexList = packed struct(u32) {
                base_offset: u28,
                _unused0: u3 = 0,
                size: IndexFormat,
            };

            pub const DrawFunction = packed struct(u32) {
                pub const drawing: DrawFunction = .{ .mode = .drawing };
                pub const config: DrawFunction = .{ .mode = .config };
                pub const Mode = enum(u1) { drawing, config };

                mode: Mode,
                _: u31 = 0,
            };

            pub const AttributesTotal = packed struct(u32) {
                num: u4,
                _: u28 = 0,

                pub fn initTotal(num: u4) AttributesTotal {
                    return .{ .num = num };
                }
            };

            pub const FixedAttributeIndex = packed struct(u32) {
                pub const immediate_mode: FixedAttributeIndex = .{ .index = 0xF };

                index: u4,
                _unused0: u28 = 0,

                pub fn initIndex(index: u4) FixedAttributeIndex {
                    std.debug.assert(index <= 11);
                    return .{ .index = index };
                }
            };

            pub const Config = packed struct(u32) {    
                pub const GeometryUsage = enum(u2) { disabled, enabled = 2 }; 

                geometry_shader_usage: GeometryUsage = .disabled,
                _unused0: u6 = 0,
                drawing_triangles: bool = false,
                _unknown0: u1 = 0,
                _unused1: u6 = 0,
                _unknown1: u4 = 0,
                _unused2: u11 = 0,
                use_reserved_geometry_subdivision: bool = false,
            };

            pub const Config2 = packed struct(u32) {
                inputting_vertices_or_draw_arrays: bool = false,
                _unused0: u7 = 0,
                drawing_triangles: bool = false,
                _unused1: u23 = 0,
            };

            attribute_buffer_base: AlignedPhysicalAddress(.@"16", .@"8"),
            attribute_buffer_format_low: AttributeBufferFormatLow,
            attribute_buffer_format_high: AttributeBufferFormatHigh,
            attribute_buffer: [12]AttributeBuffer,
            attribute_buffer_index_list: AttributeIndexList,
            attribute_buffer_num_vertices: u32,
            config: Config,
            attribute_buffer_first_index: u32,
            _unknown0: [2]u32,
            post_vertex_cache_num: u32,
            attribute_buffer_draw_arrays: Trigger,
            attribute_buffer_draw_elements: Trigger,
            _unknown1: u32,
            clear_post_vertex_cache: Trigger,
            fixed_attribute_index: FixedAttributeIndex,
            fixed_attribute_data: F7_16x4,
            _unknown2: [2]u32,
            command_buffer_size: [2]u32,
            command_buffer_address: [2]u32,
            command_buffer_jump: [2]u32,
            _unknown3: [4]u32,
            vertex_shader_input_attributes: AttributesTotal,
            _unknown4: u32,
            enable_geometry_shader_configuration: EnableBit,
            start_draw_function: DrawFunction,
            _unknown5: [4]u32,
            vertex_shader_output_map_total_2: AttributesTotal,
            _unknown6: [6]u32,
            vertex_shader_output_map_total_1: AttributesTotal,
            geometry_shader_misc0: u32,
            config_2: Config2,
            geometry_shader_misc1: u32,
            _unknown7: u32,
            _unknown8: [8]u32,
            primitive_config: PrimitiveConfig,
            restart_primitive: Trigger,
        };

        pub const Shader = extern struct {
            pub const Entry = packed struct(u32) {
                entry: u16,
                _: u16 = 0x7FFF,

                pub fn initEntry(entry: u16) Entry {
                    return .{ .entry = entry };
                }
            };

            pub const InputBufferConfig = packed struct(u32) {
                num_input_attributes: u4,
                _unused0: u4 = 0,
                use_geometry_shader_subdivision: bool = false,
                _unused1: u18 = 0,
                enabled_for_geometry_0: bool = false,
                _unknown0: u1 = 0,
                enabled_for_vertex_0: bool = false,
                _unused2: u1 = 0,
                enabled_for_vertex_1: bool = false,
            };
            
            pub const OutputMask = packed struct(u32) {
                o0_enabled: bool = false,
                o1_enabled: bool = false,
                o2_enabled: bool = false,
                o3_enabled: bool = false,
                o4_enabled: bool = false,
                o5_enabled: bool = false,
                o6_enabled: bool = false,
                o7_enabled: bool = false,
                o8_enabled: bool = false,
                o9_enabled: bool = false,
                o10_enabled: bool = false,
                o11_enabled: bool = false,
                o12_enabled: bool = false,
                o13_enabled: bool = false,
                o14_enabled: bool = false,
                o15_enabled: bool = false,
                _unknown0: u16 = 0,
            };

            pub const CodeTransferIndex = packed struct(u32) {
                index: u12,
                _: u20 = 0,

                pub fn initIndex(index: u12) CodeTransferIndex {
                    return .{ .index = index };
                }
            };

            pub const OperandDescriptorsIndex = packed struct(u32) {
                index: u7,
                _: u25 = 0,

                pub fn initIndex(index: u7) OperandDescriptorsIndex {
                    return .{ .index = index };
                }
            };

            pub const FloatUniformConfig = packed struct(u32) {
                pub const Mode = enum(u1) { f8_23, f7_16 };

                index: FloatConstantRegister,
                _unused0: u24 = 0,
                mode: Mode,
            };

            pub const AttributePermutationLow = packed struct(u32) {
                attribute_0: InputRegister = .v0,
                attribute_1: InputRegister = .v1,
                attribute_2: InputRegister = .v2,
                attribute_3: InputRegister = .v3,
                attribute_4: InputRegister = .v4,
                attribute_5: InputRegister = .v5,
                attribute_6: InputRegister = .v6,
                attribute_7: InputRegister = .v7,
            };

            pub const AttributePermutationHigh = packed struct(u32) {
                attribute_8: InputRegister = .v8,
                attribute_9: InputRegister = .v9,
                attribute_10: InputRegister = .v10,
                attribute_11: InputRegister = .v11,
                attribute_12: InputRegister = .v12,
                attribute_13: InputRegister = .v13,
                attribute_14: InputRegister = .v14,
                attribute_15: InputRegister = .v15,
            };

            bool_uniform: u32,
            int_uniform: [4]u32,
            _unused0: [4]u32,
            input_buffer_config: InputBufferConfig,
            entrypoint: Entry,
            attribute_permutation_low: AttributePermutationLow,
            attribute_permutation_high: AttributePermutationHigh,
            output_map_mask: OutputMask,
            _unused1: u32,
            code_transfer_end: Trigger,
            float_uniform_index: FloatUniformConfig,
            float_uniform_data: [8]u32,
            _unused2: [2]u32,
            code_transfer_index: CodeTransferIndex,
            code_transfer_data: [8]Instruction,
            _unused3: u32,
            operand_descriptors_index: OperandDescriptorsIndex,
            operand_descriptors_data: [8]OperandDescriptor,
        };

        irq: Interrupt,
        _unused0: [40]u8,
        rasterizer: Rasterizer,
        _unused1: [64]u8,
        texturing: Texturing,
        _unused2: [36]u8,
        texturing_procedural: TexturingProcedural,
        _unused3: [32]u8,
        texturing_environment: TexturingEnvironment,
        _unused4: [8]u8,
        framebuffer: Internal.Framebuffer,
        fragment_lighting: FragmentLighting,
        _unused5: [152]u8,
        geometry_pipeline: GeometryPipeline,
        _unused6: [128]u8,
        geometry_shader: Shader,
        _unused7: [8]u8,
        vertex_shader: Shader,

        comptime {
            std.debug.assert(@offsetOf(Internal, "irq") == 0x0000);
            std.debug.assert(@offsetOf(Internal, "rasterizer") == 0x100);
            std.debug.assert(@offsetOf(Internal, "texturing") == 0x200);
            std.debug.assert(@offsetOf(Internal, "texturing_procedural") == 0x2A0);
            std.debug.assert(@offsetOf(Internal, "texturing_environment") == 0x300);
            std.debug.assert(@offsetOf(Internal, "framebuffer") == 0x400);
            std.debug.assert(@offsetOf(Internal, "fragment_lighting") == 0x500);
            std.debug.assert(@offsetOf(Internal, "geometry_pipeline") == 0x800);
            std.debug.assert(@offsetOf(Internal, "geometry_shader") == 0xA00);
            std.debug.assert(@offsetOf(Internal, "vertex_shader") == 0xAC0);
        }
    };

    hardware_id: u32,
    clock: u32,
    _unknown0: u32,
    _unused0: u32,
    psc: [2]MemoryFill,
    vram_power: VRamPower,
    irq: InterruptFlags,
    _something: u32,
    _make_something: u32,
    _backlight_or_so_0: u32,
    _unknown1: u32,
    _unknown2: u32,
    _unused1: u32,
    timing_control: [2]u32,
    stat_busy_flags: BusyFlags,
    _unknown3: u32,
    _unknown4: u32,
    _unknown5: u32,
    _unknown6: u32,
    _unused2: u32,
    traffic: TrafficStatus,
    _backlight_or_so_1: u32,
    vram_a_base_address: [*]u8,
    vram_b_base_address: [*]u8,
    _backlight_or_so_2: u32,
    _unknown7: u32,
    _unused3: [0x2C]u8,
    _unused4: [0x300]u8,
    pdc: [2]Pdc,
    _unused5: [0x600]u8 = @splat(0),
    dma: MemoryCopy,
    _unknown8: [0xF5]u32 = @splat(0),
    internal: Internal,
};

comptime {
    if (@sizeOf(Registers.Pdc) != 0x100)
        @compileError(std.fmt.comptimePrint("(@sizeOf(Pdc) == 0x{X}) and 0x{X} != 0x100!", .{ @sizeOf(Registers.Pdc), @sizeOf(Registers.Pdc) }));

    if (@sizeOf(Registers.MemoryFill) != 0x10)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryFill) == 0x{X}) and 0x{X} != 0x10!", .{ @sizeOf(Registers.MemoryFill), @sizeOf(Registers.MemoryFill) }));

    if (@sizeOf(Registers.MemoryCopy) != 0x2C)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryCopy) == 0x{X}) and 0x{X} != 0x2C!", .{ @sizeOf(Registers.MemoryCopy), @sizeOf(Registers.MemoryCopy) }));
}

pub const command = @import("gpu/command.zig");
pub const Framebuffer = @import("gpu/Framebuffer.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const zitrus_tooling = @import("zitrus-tooling");

const pica = zitrus_tooling.pica;
const OperandDescriptor = pica.encoding.OperandDescriptor;
const Instruction = pica.encoding.Instruction;
const FloatConstantRegister = pica.register.SourceRegister.Constant;
const InputRegister = pica.register.SourceRegister.Input;

const AlignedPhysicalAddress = zitrus.AlignedPhysicalAddress;
const PhysicalAddress = zitrus.PhysicalAddress;
