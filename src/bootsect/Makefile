
ASM = nasm
SRC_DIR = ../
BIN_DIR = ../../bin
CAT = cat

$(info = Compiling boot sector into a 1.44MB image file...)

disk: bootsect.bin loader.bin
	# Concatenate these two together into a binary
	$(CAT) bootsect.bin loader.bin > bootdisk.bin
	$(SRC_DIR)/util/binpad bootdisk.bin 1474560 -o $(BIN_DIR)/bootdisk.img

bootsect.bin: bootsect.asm Makefile
	$(info >>> bootsect.asm -> bootsect.bin)
	$(ASM) bootsect.asm -o bootsect.bin

loader.bin: loader.asm Makefile
	$(info >>> loader.asm -> loader.bin)
	$(ASM) loader.asm -o loader.bin
