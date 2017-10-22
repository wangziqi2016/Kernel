# Kernel

Makefile
========

In order to build, simply type "make" command under the repo's root directory. The makefile will
automatically dispatch make commands to subdirectories under ./src folder.

Use "make" without any argument to build all components and save the output to ./bin, which will be loaded
as the booting image later if you run emulation.

Use "make run" to load the boot disk and start running simulation on bochs, which is a 
handy tool for running lightweight x86 virtual machines. As an alternative, you can also use 
"make qemu" to load the boot disk and start QEMU. Both Bochs and QEMU are capable of emulating
a x86 environment. 

Bochs has the extra advantage of being able to debug and view the processor state. Before
starting the simulation, however, you will need to type command 'c' to continue bochs's execution.
As a contrast, if you run QEMU, then after typing "make qemu", the simulation immediately starts, which is 
more convenient if you just made a few small modifications and expect the code to run without debugging.

In addition, you can also use VirtualBox to load the boot image as the first floppy device and start 
the virtual machine. VirtualBox provides a slightly different environment, which is closer to a real
physical machine. For example, VirtualBox does not enable A20 gate at system startup, while both Bochs
and QEMU by default enables A20. This forces programmers to check and activate it manually in the bootloader. 

Utility
=======
Under ./src/util directory, there are a few tools that are developed to aid the development of this project.

binpatch
--------
This utility tool patchs a given binary file to a specified length, with optionally custom padding value. 
We use this tool to make a 1.44MB floppy disk out of the compiled bootloader image.

peek\_line.py
------------
Due to the way we assemble the bootloader (use "cat" command to conbine separate source files into a single flat file
before calling the assembler), when nasm finds an error in the source file, it reports the line number in the 
combined file, which is nonsense. In order to translate the combined line number into individual files, we developed
the peek\_line.py tool to scan each file and remember their starting line and compare the lines in the combined
source and locate each file's offset. Run "make peek\_line LINE=ddd" where "ddd" is the line number in combined
loader source file. 

Dependency
=========

**nasm**: The assembler we use to translate the bootloader into a binary file

**Bochs**: The emulation tool for debugging real mode code and protected mode code

**QEMU**: An alternative to Bochs

**Python**: To run some of the utility tools
