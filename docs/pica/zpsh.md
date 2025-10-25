# PICA200 shader

**This document is marked as a DRAFT, it is NOT final**

This new file format is very minimalist and is the default output format for a file assembled by zitrus.

It has been designed from scratch with iterative changes based on real world use-cases (mango)
 
All fields are little endian unless explicitly told otherwise and all types are described with `zig` syntax.

## Header

The main header of the binary, starting at offset `0x00`

| Field     | Type                     | Notes                      |
|:---------:|:------------------------:|----------------------------|
| `magic`   | `[4]u8`                  | Must be `ZPSH`             |
| `shader`  | `bitpacked struct(u32)`  | Starting from the LSb, the first `u12` is the number of entrypoints, the next `u12` is the number of instructions **minus one**, a valid PICA200 shader must have at least one instruction, `end`. The last `u8` is the number of instruction operand descriptors, **the value must be no larger than 128**|
| `entry_string_table_size` | `u16`    | Size **in `u32`s** of the entrypoint string table |
| `flags`   | `bitpacked struct(u8)`   | Reserved                   |
| `header_size` | `u8`                 | Real size **in `u32`s** of the **Header**, allows for *forward compatibility* |

#### `shader` bit layout

| 31...24 | 23...12 | 11...0 |
|:-------:|:-------:|:------:|
| descriptors (`u8`) | instructions_minus_one (`u12`) | entrypoints (`u12`) |

## Instruction & Operand Descriptors

Instructions (`shader.instructions_minus_one` + 1) and operand descriptors (`shader.descriptors`), starting at offset `header_size * @sizeOf(u32)`

## Entrypoint string table

This string table stores unique `0`-terminated `UTF-8` strings for entrypoint names, starting at offset `(header_size + shader.instructions_minus_one + 1 + shader.descriptors) * @sizeOf(u32)`

## Entrypoint Header

Entrypoints follow, they're dynamically sized as constants follow this header.
  
Starting at offset `(header_size + shader.instructions_minus_one + 1 + shader.descriptors + entry_string_table_size) * @sizeOf(u32)`

| Field                | Type                     | Notes                                                |
|:--------------------:|:------------------------:|------------------------------------------------------|
| `name_string_offset` | `u32`                    | Offset of the name in the entrypoint string table    |
| `instruction_offset` | `u16`                    | Entry instruction offset, must be less than 4096     |
| `info`               | `bitpacked struct(u16)`  | Shader type and parameters, see below for the layout |
| `boolean_constant_mask` | `bitpacked struct(u16)`  | Each bit represents the state of the constant boolean register `bX` |
| `integer_constant_mask` | `bitpacked struct(u16)`  | Each bit represents whether a constant for the integer register `iX` follows, the remaining 12-bits are reserved and must be zeroed. |
| `floating_constant_mask` | `extern struct`  | Each bit represents represents whether a constant for the floating register `fX` follows, the remaining bits are reserved and must be zeroed. |
| `output_mask` | `bitpacked struct(u16)`  | Each bit represents represents whether an output map for the output register `oX` follows. |

#### `boolean_constant_mask` bit layout

Each bit represents the constant value for the register at that bit index.

| 16  | ... | 0  |
|:---:|:---:|:--:|
| b15 | bN  | b0 |

#### `integer_constant_mask` bit layout

Each bit represents whether a constant value for the register at that bit index follows after the header.

Constants are sorted for each bit, that is, if bits `0` and `3` are set, the first constant will be for register `i0`
and the second for `i3`.

|  16...4  | 3  | 2  | 1  | 0  |
|:--------:|:--:|:--:|:--:|:--:|
| reserved | i3 | i2 | i1 | i0 |

#### `floating_constant_mask` layout

Each bit represents whether a constant value for the register at that bit index follows after the header.

The `extern struct` has this layout:

| Field                | Type                     | Notes                                                      |
|:--------------------:|:------------------------:|------------------------------------------------------------|
| `low`                | `bitpacked struct(u32)`  | Whether a constant value follows for registers `f0`-`f31`  |
| `mid`                | `bitpacked struct(u32)`  | Whether a constant value follows for registers `f32`-`f63` |
| `high`               | `bitpacked struct(u32)`  | Whether a constant value follows for registers `f64`-`f95` |

Bit layout for each field follows the same structure as `boolean_constant_mask` and `integer_constant_mask`.

#### `output_mask` bit layout

Each bit represents whether an output map for the register at that bit index follows after the header.

| 16  | ... | 0  |
|:---:|:---:|:--:|
| o15 | oN  | o0 |

### Entrypoint constants and output maps

Each entrypoint can be considered as a different `shader module` that shares instructions with others. As such, they have different sets
of constants and output maps.

The layout is the following:
- Entrypoint Header
- Integer constants, one for each bit set in `integer_constant_mask`
- Floating constants, one for each bit set in `floating_constant_mask`
- Output maps, one for each bit set in `output_mask`

#### Integer constant

A `[4]u8` representing a 4-component vector with layout `xyzw`.

#### Floating constant

A packed 4-component `F7_16` vector in the format required by the PICA200. It can be seen as storing all `F7_16` components packed in an `[3]u32` and doing a `swap` of the first and last `u32`.

#### Output map

An map describing output semantics for each component of the specified output. They're in the format required by the PICA200.
