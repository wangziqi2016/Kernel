/*
 * ofs.c - A file for simulating the UNIX SYSTEM V Old File System
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define DEFAULT_SECTOR_SIZE 512

// This enum defines the type of the storage
enum STORAGE_TYPE {
  // We use a memory chunk to simulate storage
  STORAGE_TYPE_MEM = 0,
  // We use a file to simulate storage
  STORAGE_TYPE_FILE = 1,
};

// This defines the storage we use
typedef struct Storage_p {
  int type;
  // Number of bytes per sector
  int sector_size;
  // Either we use it as a file pointer or as a data pointer
  union {
    FILE *fp;
    uint8_t *data_p;
  };
  // Read and write function call backs
  void (*read)(struct Storage_p *disk_p, uint64_t lba, void *buffer);
  void (*write)(struct Storage_p *disk_p, uint64_t lba, void *buffer);
} Storage;

int main() {
  return 0;
}