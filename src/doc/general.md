
# General Rules of Coding

This file describes the general rules of coding in the Kernal repo, including file formatting, naming convention, 
variable declaration rules, etc. Coding rules that are specific to individual modules and module documentation is 
contained in separate files.

## Makefile Commands and Testing

This repo has a hierarchy of Makefiles. The root directory makefile is responsible for setting up common environmental
variables, and dispatching commands to the corresponding directories. Each subdirectory has its own makefile, which
*may* also invoke the makefile of other subdirectories. 

The final testing command is defined within the root level makefile. Currently we use qemu as our major way of performing
quick testing. The qemu command line argument can be found in: https://www.mankier.com/1/qemu. In our testing environment,
we instruct qemu to load a compiled 1.44MB standard floppy disk file. The disk file is located under ``bin`` directory
and is named ``bootdisk.img``. More details of the internal format of the disk image will be disclosed below.

In order to test, type ``make qemu`` under the root and the qemu window should pop up. Use ``make run`` to run bochs which
is our secondary way of testing. Bochs requires a configuration file, which is located under ``test`` directory.

In order to convert a global line number (as a result of combining module files before assmebly, see below) to the line 
number in the corresponding file before concatenation, use command ``LINE=[line # in global file] make peekfile``, and 
the output contains both the individual file name and the local line number.

## Loader Module Assembly and Linking Process

The loader (under ``bootsect``) consists of separate modules, each of which has its own assembly source file. Modules are 
concatenated using ``cat`` utility before they are translated by the assembler, to provide global visibility of symbols. 
As a result, there is no linking phase. The combined file is named ``_loader_modules.tmp`` under ``bootsect`` directory. 

Since no conventional linking process is involved, module files must be coded in a way that allows the assembler and utility 
to recognize the original file after concatenation. We achieve this by adding special marks at the beginning and the end of the 
file. First, to avoid file contents getting mixed up after the concatenation, each module source file must end with one or more new 
line character. Second, to allow the utility to convert a line number in the conbined file to the number in individual files, 
at the physical first line of each file, there must be a label of form ``_[module file name without .asm suffix]_start:``.

The loader assembly process is described as follows. There are three stages. In the first stage, all module files with a naming
pattern ``loader_*`` are concatenated together into a file ``_loader_modules.tmp``. In the second stage, the combined loader
module is concatenated with ``loader.asm`` which is the loader entry point (must begin from the first byte of the module file)
and ``sect_endmark.asm`` which defines an end-of-loader mark (similar to 0x55AA but is at the end of the entire loader). 
This stage generates an intermediate file ``_loader.tmp``. In the third stage, the file ``_loader.tmp`` is translated by the 
nasm assembler. The assembler outputs two files: ``loader.bin``, the binary loader file with the entry point being at 
offset 0, and ``loader.map`` which describes the offset of symbols and segments in the binary.

In order to generate the final disk image file, we still need a bootloader. The bootloader source is named ``bootsect.asm``
and stored under ``src/bootsect``. The bootloader is assembled into ``bootsect.bin`` under the same directory. The binary 
bootloader and the loader module is then combined into the boot file ``bootdisk.bin`` using ``cat``.

The ``bootdisk.bin`` is then padded with zero until its size reaches 1.44MB, which is the size of a standard floppy disk file.
The utility we use for the padding is under ``util`` directory, and is called ``binpad``. 

## Register Usage Convention

Without special noting, all source code must follow a global register usage and argument passing convention. Interrupt 
Service Routines and other hardware oriented routines are not included. 

In the child function, register AX, CX, and DX are allowed to be changed without saving and restoring. Register BX, SI, 
DI, SP, BP must be saved.

Segment registers DS and ES are generally not preserved. Interrupt service routines should not assume DS or ES pointing 
to the system segment. If ISR needs to access a system segment, it should always save the original value first, and 
then populate the register with ``SYS_DS``. It is, however, recommended that normal functions not changing the DS register
unless necessary (e.g. in ``loader_mem.asm`` when performing memory copy). If a function reloads DS register, it should 
restore the DS value before calling a child function, such that the child function can assume that DS always points 
to the system segment. SS register should never be changed under all circumstances except in ISR. The usage of FS and GS
are not defined, and they are only recommended to be used for local purposes. 

## Calling Convention

Without special noting, functions are called in C language convention: Arguments are pushed onto the stack right-to-left.
Byte arguments (e.g. disk letter) should be converted to 16 bit words. 32 bit dwords should be pushed little-endian (i.e.
higher 16 bits first, then lower 16 bits). Segment-offset pairs should observe the convention that segment is pushed 
first and then the offset. The caller is responsible for clearing up the arguments after function returns. This allows
printf() to be implemented in a more robust manner (could return safely even if arguments and the format sting mismatch).

Reasonably large functions should use stack frames to simplify argument and local variable access. If the function is 
small and simple, or is just a wrapper, stack frames may be omitted, and arguments may be passed using registers. In this
case the function must define clearly its expected argument list in the declaration header. The first, second, ... , arguments 
of near functions are accessed via the ``BP`` register using ``[BP + 4]``, ``[BP + 6]``, .... ``[BP + 0]`` and ``[BP + 2]`` 
must not be changed because they are the old BP and the return address, respectively. For far functions,  argument list should
begin at ``[BP + 6]``. For ISR, there is no argument list, but there are three words (6 bytes) on the stack that must not 
be modified.

Function returns a value in AX if it is 16 bits, or DX:AX if 32 bits. On failure condition, CF should be set, and the 
content of AX should be either undefined, or an error code that allows the calling function to recover from the failure.

## Global Memory Map

Under real mode, the kernel could only access the lower 640KB memory, from 0x00000 to 0xA0000. We describe the memory map 
of the kernel as follows. The stack segment is located at the highest end of the 640KB address space. The stack segment register
is initialized to 0x9000, and stack pointer is 0xFFF0. The stack top is therefore 0x9FFFF0 and grows downwards until the 
full 64KB segment is used up (which should be a fatal system error, but due to the lack of permission check, this will just
be silently ignored). In practice, we expect that 64KB stack segment is more than sufficient to support most of the tasks,
so stack segment should remain the same all the time.

The system loader will be booted into a high address just under the stack at 0x9000. During bootstrap, the floppy disk image 
will be copied to address 9000:0000h, including the bootloader itself. The entry point of the loader is therefore 9000:0200h.
The system DS is on the same segment as the loader, i.e. DS is initialized to 0x9000 and will not be changed frequently.
All variables defined in the loader module will use an implicit offset of 0x200 plus their relative offsets in the loader
binary.

If A20 is enabled successfully (which should always be the case, because otherwise the system will not boot), the system
can address an extra segment of size 64KB - 16B. This chunk of memory is reserved by the kernel for large allocation, e.g.
disk buffers. The system use segment 0xFFFF and offset 0x0010 to address the first byte of the chunk (0x10000), and offset
0xFFFF to address the last byte of the chunk (0x1FFEF). Note that due to the address generation mechanism of 8086, we cannot 
address the full 64KB range, because the maximum possible address is 0x1FFEF.

Static system data that cannot be released will be allocated during system initialization. The binary does not reserve 
space for these static data. Instead, at module initialization time, the BSS allocation function must be called to 
reserve space from the end of the system data area. The BSS grows downwards like stack segment. BSS allocation would fail
if the allocation will cause the loader to be overwritten (since they are on the same segment). The advantage of allocating
static BSS data from the system segment is that these variables can be referred to using the system DS. For infrequently
used data, they can be allocated in the A20 BSS segment using another routine. Before accessing this segment, a segment
register must be loaded with LARGE_BSS_SEG. 

The definition of system segments can be found in the beginning of ``loader.asm``.