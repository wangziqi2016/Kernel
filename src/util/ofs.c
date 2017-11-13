/*
 * ofs.c - A file for simulating the UNIX SYSTEM V Old File System
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>

#define DEFAULT_SECTOR_SIZE 512

// This enum defines the type of the storage
enum STORAGE_TYPE {
  // We use a memory chunk to simulate storage
  STORAGE_TYPE_MEM = 0,
  // We use a file to simulate storage
  STORAGE_TYPE_FILE = 1,
};

// This defines the storage we use
typedef struct Storage_t {
  int type;
  // Number of bytes per sector
  size_t sector_size;
  // Number of sectors in total in the storage
  size_t sector_count;
  // Either we use it as a file pointer or as a data pointer
  union {
    FILE *fp;
    uint8_t *data_p;
  };
  // Read and write function call backs
  void (*read)(struct Storage_t *disk_p, uint64_t lba, void *buffer);
  void (*write)(struct Storage_t *disk_p, uint64_t lba, void *buffer);
  void (*free)(struct Storage_t *disk_p);
} Storage;

/*
 * fatal_error() - Reports error and then exit
 */
void fatal_error(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  exit(1);
}

/*
 * mem_read() - Reads a sector into the given buffer
 */
void mem_read(Storage *disk_p, uint64_t lba, void *buffer) {
  if(lba >= disk_p->sector_count) {
    fatal_error("Invalid LBA for read: %lu", lba);
  }

  size_t offset = lba * disk_p->sector_size;
  memcpy(buffer, disk_p->data_p + offset, disk_p->sector_size);

  return;
}

/*
 * mem_write() - Writes a buffer of data into the memory
 */
void mem_write(Storage *disk_p, uint64_t lba, void *buffer) {
  if(lba >= disk_p->sector_count) {
    fatal_error("Invalid LBA for read: %lu", lba);
  }

  size_t offset = lba * disk_p->sector_size;
  memcpy(disk_p->data_p + offset, buffer, disk_p->sector_size);

  return;
}

/*
 * mem_free() - Frees a memory object
 */
void mem_free(Storage *disk_p) {
  free(disk_p->data_p);
  return;
}

int main() {
  return 0;
}