// https://www.3dbrew.org/wiki/GPU/Internal_Registers

pub const Header = packed struct(u32) {
    id: Id,
    mask: u4,
    extra: u8,
    _unused0: u3 = 0,
    consecutive_writing: bool,
};

pub const Id = enum(u16) {
    // Miscellaneous (0x000-0x03F)
    finalize = 0x0010,

    // Rasterizer (0x040-0x07F)
    faceculling_config = 0x040,
    viewport_width = 0x41,
    viewport_invw,
    viewport_height,
    viewport_invh,

    fragop_clip = 0x047,
    fragop_clip_data0,
    fragop_clip_data1,
    fragop_clip_data2,
    fragop_clip_data3,

    depthmap_scale = 0x04D,
    depthmap_offset,

    sh_outmap_total = 0x04F,
    sh_outmap_o0,
    sh_outmap_o1,
    sh_outmap_o2,
    sh_outmap_o3,
    sh_outmap_o4,
    sh_outmap_o5,
    sh_outmap_o6,

    earlydepth_func = 0x061,
    earlydepth_test1,
    earlydepth_clear,

    sh_outattr_mode = 0x064,

    scissortest_mode = 0x065,
    scissortest_pos,
    scissortest_dim,

    viewport_xy = 0x068,

    earlydepth_data = 0x06A,

    depthmap_enable = 0x06D,

    renderbuf_dim = 0x06E,

    sh_outattr_clock = 0x06F,

    // Texturing (0x080-0x0FF)
    texunit_config = 0x080,
    texunit0_border_color = 0x081,
    texunit0_dim,
    texunit0_param,
    texunit0_lod,
    texunit0_addr1 = 0x085,
    texunit0_addr2,
    texunit0_addr3,
    texunit0_addr4,
    texunit0_addr5,
    texunit0_addr6,
    texunit0_shadow,
    texunit0_type = 0x08E,

    lighting_enable0 = 0x08F,

    texunit1_border_color = 0x091,
    texunit1_dim,
    texunit1_param,
    texunit1_lod,
    texunit1_type,

    texunit2_border_color = 0x099,
    texunit2_dim,
    texunit2_param,
    texunit2_lod,
    texunit2_type,

    texunit3_proctex0 = 0x0A8,
    texunit3_proctex1,
    texunit3_proctex2,
    texunit3_proctex3,
    texunit3_proctex4,
    texunit3_proctex5,

    proctex_lut = 0xAF,
    proctex_lut_data0,
    proctex_lut_data1,
    proctex_lut_data2,
    proctex_lut_data3,
    proctex_lut_data4,
    proctex_lut_data5,
    proctex_lut_data6,
    proctex_lut_data7,

    texenv0_source = 0x0C0,
    texenv0_operand,
    texenv0_combiner,
    texenv0_color,
    texenv0_scale,

    texenv1_source = 0x0C8,
    texenv1_operand,
    texenv1_combiner,
    texenv1_color,
    texenv1_scale,

    texenv2_source = 0x0D0,
    texenv2_operand,
    texenv2_combiner,
    texenv2_color,
    texenv2_scale,

    texenv3_source = 0x0D8,
    texenv3_operand,
    texenv3_combiner,
    texenv3_color,
    texenv3_scale,

    texenv_update_buffer = 0x0E0,

    fog_color = 0x0E1,

    gas_attenuation = 0x0E4,
    gas_accmax,

    fog_lut_index = 0x0E6,
    fog_lut_data0 = 0x0E8,
    fog_lut_data1,
    fog_lut_data2,
    fog_lut_data3,
    fog_lut_data4,
    fog_lut_data5,
    fog_lut_data6,
    fog_lut_data7,

    texenv4_source = 0x0F0,
    texenv4_operand,
    texenv4_combiner,
    texenv4_color,
    texenv4_scale,

    texenv5_source = 0x0F8,
    texenv5_operand,
    texenv5_combiner,
    texenv5_color,
    texenv5_scale,

    // Framebuffer (0x100-0x13F)
    color_operation = 0x100,
    blend_func = 0x101,
    logic_op = 0x102,
    blend_color = 0x103,
    fragop_alpha_test = 0x104,
    stencil_test = 0x105,
    stencil_op,
    depth_color_mask = 0x107,

    framebuffer_invalidate = 0x110,
    framebuffer_flush,
    framebuffer_read,
    framebuffer_write,
    colorbuffer_read,
    colorbuffer_write,
    depthbuffer_read,
    depthbuffer_write,
    depthbuffer_format,
    colorbuffer_format,

    earlydepth_test2 = 0x118,

    framebuffer_block32 = 0x11B,

    depthbuffer_loc = 0x11C,
    colorbuffer_loc = 0x11D,

    framebuffer_dim = 0x11E,

    gas_light_xy = 0x120,
    gas_light_z,
    gas_light_z_color,
    gas_lut_index,
    gas_lut_data,

    gas_deltaz_depth = 0x126,

    fragop_shadow = 0x130,

    // Fragment lighting (0x140-0x1FF)
    light0_specular0 = 0x140,
    light0_specular1,
    light0_diffuse,
    light0_ambient,
    light0_xy,
    light0_z,
    light0_spotdir_xy,
    light0_spotdir_z,

    light0_config = 0x149,
    light0_attenuation_bias = 0x14A,
    light0_attenuation_scale,

    light1_specular0 = 0x150,
    light1_specular1,
    light1_diffuse,
    light1_ambient,
    light1_xy,
    light1_z,
    light1_spotdir_xy,
    light1_spotdir_z,

    light1_config = 0x159,
    light1_attenuation_bias = 0x15A,
    light1_attenuation_scale,

    light2_specular0 = 0x160,
    light2_specular1,
    light2_diffuse,
    light2_ambient,
    light2_xy,
    light2_z,
    light2_spotdir_xy,
    light2_spotdir_z,

    light2_config = 0x169,
    light2_attenuation_bias = 0x16A,
    light2_attenuation_scale,

    light3_specular0 = 0x170,
    light3_specular1,
    light3_diffuse,
    light3_ambient,
    light3_xy,
    light3_z,
    light3_spotdir_xy,
    light3_spotdir_z,

    light3_config = 0x179,
    light3_attenuation_bias = 0x17A,
    light3_attenuation_scale,

    light4_specular0 = 0x180,
    light4_specular1,
    light4_diffuse,
    light4_ambient,
    light4_xy,
    light4_z,
    light4_spotdir_xy,
    light4_spotdir_z,

    light4_config = 0x189,
    light4_attenuation_bias = 0x18A,
    light4_attenuation_scale,

    light5_specular0 = 0x190,
    light5_specular1,
    light5_diffuse,
    light5_ambient,
    light5_xy,
    light5_z,
    light5_spotdir_xy,
    light5_spotdir_z,

    light5_config = 0x199,
    light5_attenuation_bias = 0x19A,
    light5_attenuation_scale,

    light6_specular0 = 0x1A0,
    light6_specular1,
    light6_diffuse,
    light6_ambient,
    light6_xy,
    light6_z,
    light6_spotdir_xy,
    light6_spotdir_z,

    light6_config = 0x1A9,
    light6_attenuation_bias = 0x1AA,
    light6_attenuation_scale,

    light7_specular0 = 0x1B0,
    light7_specular1,
    light7_diffuse,
    light7_ambient,
    light7_xy,
    light7_z,
    light7_spotdir_xy,
    light7_spotdir_z,

    light7_config = 0x1B9,
    light7_attenuation_bias = 0x1BA,
    light7_attenuation_scale,

    lighting_ambient = 0x1C0,

    lighting_num_lights = 0x1C2,
    lighting_config0,
    lighting_config1,
    lighting_lut_index,
    lighting_enable1,

    lighting_lut_data0 = 0x1C8,
    lighting_lut_data1,
    lighting_lut_data2,
    lighting_lut_data3,
    lighting_lut_data4,
    lighting_lut_data5,
    lighting_lut_data6,
    lighting_lut_data7,
    lighting_lutinput_abs,
    lighting_lutinput_select,
    lighting_lutinput_scale,

    lighting_light_permutation = 0x1D9,

    // Geometry pipeline (0x200-0x27F)
    attribbuffers_loc = 0x200,
    attribbuffers_format_low,
    attribbuffers_format_high,
    attribbuffer0_offset = 0x203,
    attribbuffer0_config1,
    attribbuffer0_config2,
    attribbuffer1_offset,
    attribbuffer1_config1,
    attribbuffer1_config2,
    attribbuffer2_offset,
    attribbuffer2_config1,
    attribbuffer2_config2,
    attribbuffer3_offset,
    attribbuffer3_config1,
    attribbuffer3_config2,
    attribbuffer4_offset,
    attribbuffer4_config1,
    attribbuffer4_config2,
    attribbuffer5_offset,
    attribbuffer5_config1,
    attribbuffer5_config2,
    attribbuffer6_offset,
    attribbuffer6_config1,
    attribbuffer6_config2,
    attribbuffer7_offset,
    attribbuffer7_config1,
    attribbuffer7_config2,
    attribbuffer8_offset,
    attribbuffer8_config1,
    attribbuffer8_config2,
    attribbuffer9_offset,
    attribbuffer9_config1,
    attribbuffer9_config2,
    attribbuffer10_offset,
    attribbuffer10_config1,
    attribbuffer10_config2,
    attribbuffer11_offset,
    attribbuffer11_config1,
    attribbuffer11_config2,
    indexbuffer_config,
    numvertices,
    geostage_config,
    vertex_offset,

    post_vertex_cache_num = 0x22D,
    drawarrays,
    drawelements,

    vtx_func = 0x231,
    fixedattrib_index,
    fixedattrib_data0,
    fixedattrib_data1,
    fixedattrib_data2,

    cmdbuf_size0 = 0x238,
    cmdbuf_size1,
    cmdbuf_addr0,
    cmdbuf_addr1,
    cmdbuf_jump0,
    cmdbuf_jump1,

    vsh_num_attr = 0x242,
    vsh_com_mode = 0x244,
    start_draw_func0,

    vsh_outmap_total1 = 0x24A,
    vsh_outmap_total2 = 0x251,
    gsh_misc0,
    geostage_config2,
    gsh_misc1,

    primitive_config = 0x25E,
    restart_primitive,

    // Shader (0x280-0x2DF)

    // Geometry
    gsh_booluniform = 0x280,
    gsh_intuniform_i0,
    gsh_intuniform_i1,
    gsh_intuniform_i2,
    gsh_intuniform_i3,

    gsh_inputbuffer_config = 0x289,
    gsh_entrypoint,
    gsh_attributes_permutation_low,
    gsh_attributes_permutation_high,
    gsh_outmap_mask,

    gsh_codetransfer_end = 0x28F,
    gsh_floatuniform_index,
    gsh_floatuniform_data0,
    gsh_floatuniform_data1,
    gsh_floatuniform_data2,
    gsh_floatuniform_data3,
    gsh_floatuniform_data4,
    gsh_floatuniform_data5,
    gsh_floatuniform_data6,
    gsh_floatuniform_data7,

    gsh_codetransfer_index = 0x29B,
    gsh_codetransfer_data0,
    gsh_codetransfer_data1,
    gsh_codetransfer_data2,
    gsh_codetransfer_data3,
    gsh_codetransfer_data4,
    gsh_codetransfer_data5,
    gsh_codetransfer_data6,
    gsh_codetransfer_data7,

    gsh_opdescs_index = 0x2A5,
    gsh_opdescs_data0,
    gsh_opdescs_data1,
    gsh_opdescs_data2,
    gsh_opdescs_data3,
    gsh_opdescs_data4,
    gsh_opdescs_data5,
    gsh_opdescs_data6,
    gsh_opdescs_data7,

    // Vertex
    vsh_booluniform = 0x2B0,
    vsh_intuniform_i0,
    vsh_intuniform_i1,
    vsh_intuniform_i2,
    vsh_intuniform_i3,

    vsh_inputbuffer_config = 0x2B9,
    vsh_entrypoint,
    vsh_attributes_permutation_low,
    vsh_attributes_permutation_high,
    vsh_outmap_mask,

    vsh_codetransfer_end = 0x2BF,
    vsh_floatuniform_index,
    vsh_floatuniform_data0,
    vsh_floatuniform_data1,
    vsh_floatuniform_data2,
    vsh_floatuniform_data3,
    vsh_floatuniform_data4,
    vsh_floatuniform_data5,
    vsh_floatuniform_data6,
    vsh_floatuniform_data7,

    vsh_codetransfer_index = 0x2CB,
    vsh_codetransfer_data0,
    vsh_codetransfer_data1,
    vsh_codetransfer_data2,
    vsh_codetransfer_data3,
    vsh_codetransfer_data4,
    vsh_codetransfer_data5,
    vsh_codetransfer_data6,
    vsh_codetransfer_data7,

    vsh_opdescs_index = 0x2D5,
    vsh_opdescs_data0,
    vsh_opdescs_data1,
    vsh_opdescs_data2,
    vsh_opdescs_data3,
    vsh_opdescs_data4,
    vsh_opdescs_data5,
    vsh_opdescs_data6,
    vsh_opdescs_data7,
};

pub const CullingMode = enum(u2) {
    none,
    front,
    back,
};

pub const OutputMap = packed struct(u28) {
    pub const Semantic = enum(u4) {
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
        texture_coordinate_2_u = 0x12,
        texture_coordinate_2_v,
        unused = 0x1F,
    };

    x: Semantic,
    y: Semantic,
    z: Semantic,
    w: Semantic,
};

pub const Queue = struct {
    buffer: []align(8) u32,
    current_index: usize,

    pub fn initBuffer(buffer: []align(8) u32) Queue {
        std.debug.assert(std.mem.isAligned(buffer.len, 4));

        return .{
            .buffer = buffer,
            .current_index = 0,
        };
    }
};

const std = @import("std");

const zitrus = @import("zitrus");
const zitrus_tooling = @import("zitrus-tooling");
const pica = zitrus_tooling.pica;

const gpu = zitrus.gpu;
