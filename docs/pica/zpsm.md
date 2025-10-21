# Zitrus PICA200 shader assembly language

This is yet another PICA200 shader assembler focused on simplicity. It is a simple 2-pass assembler where first 
labels and directives are processed and then instructions are assembled as their length is fixed.
  
Supports diagnostics for syntax and semantic errors but no other diagnostics will be shown 
for assembler simplicity. It is expected that you already know the PICA200 pitfalls.

## Registers
```
Input:              v0-v15
Output:             o0-o15
Temporary/Normal:   r0-r15 
Floating constants: f0-f95
Integer constants:  i0-i3
Boolean constants:  b0-b15
Address:            a (only xy components available) and a.l
```

A `Source register` or `src` refers to an `Input`, `Temporary` or `Floating constant` register.
 
A `Limited source register` or `src_limited` refers to an `Input` or `Temporary` register.
 
A `Destination register` or `dst` refers to an `Output` or `Temporary` register.

## Basic Syntax

Each basic unit is a line, operands must be in the same line as the mnemonic/directive, 
one exception to this rule is an instruction preceded by a label, as it is perfectly valid. 
  
Comments start with ';', only single line comments are supported.

There's one TODO left, relative `Floating constant` source addressing with the address register.

### Directives

`.entry <label> <shader> [parameters]`

Declare an entrypoint.

`.out <entry> <oX>[.mask] <semantic>[.swizzle]`

Declare an output linked to an entrypoint.

`.set <entry> <f/i/b>X <scalar/vector>`

Declare a constant within an entrypoint.

`.alias <name> <dX>[.swizzle]`

Declare a global alias.

### Instructions

No pseudo-instructions are implemented nor planned currently. All known PICA200 instructions are implemented and expect a specific format:
  
    - unparametized: no extra operands expected
    - unary: `dst[.mask], [-]src[.swizzle]`
        - mova: `a[.mask], [-]src[.swizzle]`
    - binary: `dst[.mask], [-]src1[.swizzle], [-]src2[.swizzle]`, where one src must be a `Limited source register`.
    - flow_conditional: `condition, x, y, start_label, end_label`
        - breakc: `condition, x, y`
        - call: `start_label, end_label`
        - jmpc: `condition, x, y, start_label`
    - flow_uniform: `bX, start_label, end_label`
        - loop: `iX, end_exclusive_label`
        - jmpu: `bX, <true/false>, start_label`
    - comparison: `[-]src1[.swizzle], x_comparison, y_comparison, [-]src2[.swizzle]`
        - no, at least from what I (GasInfinity) tested in my o2DS, cmp does NOT use the destination mask, so cc[.mask] would be always cc.xy.
    - setemit: `0-2, <none/emmiting>, <cw/ccw>`
    - mad: `dst[.mask], [-]src_limited1[.swizzle], [-]src2[.swizzle], [-]src3[.swizzle]`, where two src must be a `Limited source register`.

#### Instruction list with GLSL equivalence (if any)
    - add [binary]: dst[.mask] = [-]src1[.swizzle] + [-]src2[.swizzle]
    - dp3 [binary]: dst[.mask] = dot(([-]src1[.swizzle]).xyz, ([-]src2[.swizzle]).xyz)
    - dp4 [binary]: dst[.mask] = dot([-]src1[.swizzle], [-]src2[.swizzle])
    - dph [binary]: dst[.mask] = dot(vec4(([-]src1[.swizzle]).xyz, 1.0), [-]src2[.swizzle])
    - dst [binary]: dst[.mask] = vec4(1.0, ([-]src1[.swizzle]).y * ([-]src2[.swizzle]).y, ([-]src1[.swizzle]).z, ([-]src2[.swizzle]).w)
    - ex2 [unary]: dst[.mask] = vec4(2 ^ ([-]src[.swizzle]).x)
    - lg2 [unary]: dst[.mask] = vec4(log2(([-]src[.swizzle]).x))
    - litp [unary]: TLDR: Partial lighting computation for vertex lighting
    - mul [binary]: dst[.mask] = [-]src1[.swizzle] * [-]src2[.swizzle]
    - sge [binary]: dst[.mask] = greaterThanEqual([-]src1[.swizzle], [-]src2[.swizzle])
    - slt [binary]: dst[.mask] = lessThan([-]src1[.swizzle], [-]src2[.swizzle])
    - flr [unary]: dst[.mask] = floor([-]src[.swizzle])
    - max [binary]: dst[.mask] = max([-]src1[.swizzle], [-]src2[.swizzle])
    - min [binary]: dst[.mask] = min([-]src1[.swizzle], [-]src2[.swizzle])
    - rcp [unary]: dst[.mask] = vec4(1 / ([-]src[.swizzle]).x)
    - rsq [unary]: dst[.mask] = vec4(1 / sqrt(([-]src[.swizzle]).x))
    - mova [unary]: a[.mask] = i8vec2(([-]src[.swizzle]).x, ([-]src[.swizzle]).y)
    - mov [unary]: dst[.mask] = [-]src[.swizzle]
    - @"break" [unparametized]
    - nop [unparametized]
    - end [unparametized]
    - breakc [flow_conditional]
    - call [flow_conditional]
    - callc [flow_conditional]
    - callu [flow_uniform]
    - ifu [flow_uniform]
    - ifc [flow_conditional]
    - loop [flow_uniform]
    - emit [unparametized]: EmitVertex()
    - setemit [setemit] 
    - jmpc [flow_conditional]
    - jmpu [flow_uniform]
    - cmp [comparison]: cc = bvec2(([-]src1[.swizzle]).x <comparison> ([-]src2[.swizzle]).x, ([-]src1[.swizzle]).y <comparison> ([-]src2[.swizzle]).y)
    - mad [binary]: dst[.mask] = [-]src3[.swizzle] + ([-]src2[.swizzle] * [-]src1[.swizzle])
