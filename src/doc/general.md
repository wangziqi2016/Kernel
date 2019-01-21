
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

## Module Assembly and Linking Process

The kernal consists of separate modules, each of which has its own assembly source file. Modules are concatenated
using ``cat`` utility before they are translated by the assembler, to provide global visibility of symbols. As a result, 
there is no linking phase. The combined file is named ``_loader_modules.tmp`` under ``bootsect`` directory. 

To avoid file contents getting mixed up after the concatenation, each module source file must end with a new line character.
