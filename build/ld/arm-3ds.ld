/* 
* Good sources:
* https://sourceware.org/binutils/docs/ld/Scripts.html
* https://gabi.xinuos.com/elf/
**/

OUTPUT_FORMAT("elf32-littlearm", "elf32-bigarm", "elf32-littlearm")
ENTRY(_start)

/*
* The elf file may be post-processed by zitrus, we'll maintain the same layout as:
*	- 3DSX: https://www.3dbrew.org/wiki/3DSX_Format
*	- CXI:  https://www.3dbrew.org/wiki/NCCH/Extended_Header
*
* Basically the segments are sequential in the 3DSX and CXI.
*
* PF_X = 0x1;
* PF_W = 0x2;
* PF_R = 0x4;
* */
PHDRS
{
	text   PT_LOAD FLAGS(0x4 | 0x1);
	rodata PT_LOAD FLAGS(0x4);
	data   PT_LOAD FLAGS(0x4 | 0x2);
	tls    PT_TLS;
}

/* XXX: Sections are missing, handle them if needed and when found */

SECTIONS
{
	/* You can export __base__ with `0x14000000` if you use the special memory flag */
	PROVIDE(__base__ = 0x100000);
	. = __base__;

	. = ALIGN(0x1000);
	.text : {
		KEEP(*(.text.base))
		ASSERT(SIZEOF(.prm) == 0 || (SIZEOF(.prm) > 0 && SIZEOF(.text.base) == 4), "When embedding/using program metadata, the first and only instruction in `_start` must be a branch to a function");
		*(.prm)

		*(.text*)
		*(.glue_7*)
	} : text

	. = ALIGN(0x1000);
	.rodata : {
		*(.rodata*)
	} : rodata

	.ARM.extab : {
		*(.ARM.extab*)
	} : rodata

	.ARM.exidx : {
		*(.ARM.exidx*)
	} : rodata

	. = ALIGN(0x1000);
	.data : {
		*(.data*)
	} : data

	.init_array : {
		__init_array_start = .;
		KEEP(*(SORT(.init_array.*)));
		KEEP(*(.init_array));
		__init_array_end = .;
	} : data

	.tdata : {
		*(.tdata*)
	} : data : tls

	.bss : {
		*(.bss*)
		*(COMMON)
	} : data

	.tbss : {
		*(.tbss*)
	} : data : tls

	/*
	* We won't relocate the PIE at run-time.
	*
	* As relocations are applied when post-processing it at build-time, we won't load them.
	* */
	.dynamic : { *(.dynamic) } : NONE
	.rel.dyn : { *(.rel.dyn) } : NONE
	.gnu.hash : { *(.gnu.hash) } : NONE
	.hash : { *(.hash) } : NONE
	.dynstr : { *(.dynstr) } : NONE
	.dynsym : { *(.dynsym) } : NONE
}
