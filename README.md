# Kernel

Makefile
========

In order to build, simply type "make" command under the repo's root directory. The makefile will
automatically dispatch make commands to subdirectories under ./src folder.

Use "make" without any argument to build all components and save the output to ./bin

Use "make run" to load the boot disk and start running simulation on bochs, which is a 
handy tool for running lightweight x86 virtual machines.

Use "make qemu" to load the boot disk and start QEMU, which is an alternative to bochs.

Running bochs has the extra advantage of being able to debug and view the processor state. Before
starting the simulation, however, you will need to type command 'c' to continue bochs's execution.
