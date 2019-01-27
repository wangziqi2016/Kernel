
#
# This makefile compiles test utility
#

SRC_DIR = ../
BUILD_DIR = ../../build

CXX = gcc
CXXFLAGS = -Wall -Werror -g
LDFLAGS = 

$(info = Compiling utility...)

BIN = binpad ofs
all: $(BIN)

binpad: binpad.c Makefile
	$(CXX) binpad.c -o binpad $(CXXFLAGS) $(LDFLAGS)

fat12: fat12.c Makefile
	$(CXX) fat12.c -o fat12 $(CXXFLAGS) $(LDFLAGS)

clean:
	rm -f $(BIN)
