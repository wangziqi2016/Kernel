
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

The assembly process is described as follows. There are three stages. In the first stage, all module files with a naming
pattern ``loader_*`` are concatenated together into a file ``_loader_modules.tmp``. In the second stage, the combined loader
module is concatenated with ``loader.asm`` which is the loader entry point (must begin from the first byte of the module file)
and ``sect_endmark.asm`` which defines an end-of-loader mark (similar to 0x55AA but is at the end of the entire loader). 
This stage generates an intermediate file ``_loader.tmp``. In the third stage, 
