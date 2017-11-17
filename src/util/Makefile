
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

ofs: ofs.c Makefile
	$(CXX) ofs.c -o ofs $(CXXFLAGS) $(LDFLAGS)

clean:
	rm -f $(BIN)
