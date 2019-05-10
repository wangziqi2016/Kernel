
#
# This is the main Makefile
#

# This should appear before including makefile common
SRC_DIR = ./src
BUILD_DIR = ./build 
BIN_DIR = ./bin

# This will let make shutup
MAKEFLAGS += -s

# We print the mode fir the first invocation, but 
# not the following
MODE_PRINT = 1

# This include the common make file
-include ./src/common/Makefile-common

$(info = Invoking the main compilation dispatcher...)

$(info = CXXFLAGS: $(CXXFLAGS))
$(info = LDFLAGS: $(LDFLAGS))

.PHONY: all util common bootsect clean prepare run

all: common util bootsect

# Note that calling make with -C will also pass the environmental variable set inside and by
# the shell to the subprocess of make

COMMON_OBJ = $(patsubst ./src/common/%.c, $(BUILD_DIR)/%.o, $(wildcard ./src/common/*.c))
common: 
	@$(MAKE) -C ./src/common

TEST_OBJ = $(patsubst ./src/test/%.c, $(BUILD_DIR)/%.o, $(wildcard ./src/test/*.c))
util: 
	@$(MAKE) -C ./src/util

bootsect: 
	@$(MAKE) -C ./src/bootsect

run: bootsect
	bochs -q -f ./test/bochs-ubuntu.bxrc

qemu: bootsect
	qemu-system-x86_64 -fda $(BIN_DIR)/bootdisk.img -fdb $(BIN_DIR)/testdisk.ima

peekline: 
	python $(SRC_DIR)/util/peek_line.py $(SRC_DIR)/bootsect "loader*.asm" _loader.tmp $(LINE)

clean:
	$(info >>> Cleaning files)
	$(RM) -f ./build/*
	$(RM) -f ./bin/*
	$(RM) -f *-bin

prepare:
	$(MKDIR) -p build
	$(MKDIR) -p bin

