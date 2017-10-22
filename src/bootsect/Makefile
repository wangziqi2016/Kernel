
ASM = nasm
ASM_FLAGS = -f bin
SRC_DIR = ../
BIN_DIR = ../../bin
CAT = cat

$(info = Compiling boot sector into a 1.44MB image file...)

disk: bootsect.bin loader.bin
	$(info >>> Combing binary files into a flat image)
	$(CAT) bootsect.bin loader.bin > bootdisk.bin
	$(SRC_DIR)/util/binpad bootdisk.bin 1474560 -o $(BIN_DIR)/bootdisk.img -s

bootsect.bin: bootsect.asm Makefile
	$(info >>> bootsect.asm -> bootsect.bin)
	$(ASM) $(ASM_FLAGS) bootsect.asm -o bootsect.bin

LOADER_ASMS = $(wildcard loader_*.asm)
loader.bin: loader.asm Makefile $(LOADER_ASMS) sect_endmark.asm
	$(info >>> loader.asm -> loader.bin)
	$(CAT) $(LOADER_ASMS) > _loader_modules.tmp
	$(CAT) loader.asm _loader_modules.tmp sect_endmark.asm > _loader.tmp
	$(ASM) $(ASM_FLAGS) _loader.tmp -o loader.bin
