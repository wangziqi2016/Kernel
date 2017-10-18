
ASM = nasm
SRC_DIR = ../
BIN_DIR = ../../bin
CAT = cat

$(info = Compiling boot sector into a 1.44MB image file...)

disk: bootsect.bin loader.bin
	# Concatenate these two together into a binary
	$(info >>> Combing binary files into a flat image)
	$(CAT) bootsect.bin loader.bin > bootdisk.bin
	$(SRC_DIR)/util/binpad bootdisk.bin 1474560 -o $(BIN_DIR)/bootdisk.img -s

bootsect.bin: bootsect.asm Makefile
	$(info >>> bootsect.asm -> bootsect.bin)
	$(ASM) bootsect.asm -o bootsect.bin

LOADER_ASMS = $(wildcard loader_*.asm)
loader.bin: loader.asm Makefile
	$(info >>> loader.asm -> loader.bin)
	$(CAT) $(LOADER_ASMS) > _loader_modules.tmp
	$(CAT) loader.asm _loader_modules.tmp > _loader.tmp
	$(ASM) _loader.tmp -o loader.bin
