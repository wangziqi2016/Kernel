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
