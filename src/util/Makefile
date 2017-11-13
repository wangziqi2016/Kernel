
#
# This makefile compiles test utility
#

SRC_DIR = ../
BUILD_DIR = ../../build

CXX = gcc
CXXFLAGS = -Wall -Werror
LDFLAGS = 

$(info = Compiling utility...)

all: binpad ofs

binpad: binpad.c Makefile
	$(CXX) binpad.c -o binpad $(CXXFLAGS) $(LDFLAGS)

ofs: ofs.c Makefile
	$(CXX) ofs.c -o ofs $(CXXFLAGS) $(LDFLAGS)	
