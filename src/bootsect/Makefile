
ASM = nasm
SRC_DIR = ../
BIN_DIR = ../../bin

$(info = Compiling boot sector into a 1.44MB image file...)

disk: bootsect.bin
	 $(SRC_DIR)/util/binpad bootsect.bin 1474560 -o $(BIN_DIR)/bootsect.ima

bootsect.bin: bootsect.asm Makefile
	 $(ASM) bootsect.asm -o bootsect.bin
