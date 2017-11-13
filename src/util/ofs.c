/*
 * ofs.c - A file for simulating the UNIX SYSTEM V Old File System
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <assert.h>

#define DEFAULT_SECTOR_SIZE 512

/*
 * fatal_error() - Reports error and then exit
 */
void fatal_error(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  putchar('\n');
  exit(1);
}

/*
 * info() - Prints info message
 */
void info(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  putchar('\n');
  return;
}

/////////////////////////////////////////////////////////////////////
// Storage Layer
/////////////////////////////////////////////////////////////////////

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

/*
 * get_mem_storage() - This function returns a memory storage object from 
 *                     the heap
 * 
 * The caller is responsible for freeing the object upon exit
 */
Storage *get_mem_storage(size_t sector_count) {
  Storage *disk_p = malloc(sizeof(Storage));
  if(disk_p == NULL) {
    fatal_error("Failed to allocatoe a Storage object");
  }

  disk_p->type = STORAGE_TYPE_MEM;
  disk_p->sector_count = sector_count;
  disk_p->sector_size = DEFAULT_SECTOR_SIZE;
  size_t alloc_size = disk_p->sector_count * disk_p->sector_size;
  disk_p->data_p = malloc(alloc_size);
  if(disk_p->data_p == NULL) {
    fatal_error("Run our of memory when allocating storage of %lu bytes",
                alloc_size);
  } else {
    info("  Allocating %lu bytes as storage", alloc_size);
    info("  Default sector size = %lu byte", alloc_size);
  }

  disk_p->read = mem_read;
  disk_p->write = mem_write;
  disk_p->free = mem_free;

  return disk_p;
}

/*
 * free_mem_storage() - This function frees the memory storage
 * 
 * This pointer is to be invalidated after return
 */
void free_mem_storage(Storage *disk_p) {
  if(disk_p->type != STORAGE_TYPE_MEM) {
    fatal_error("Invalid type to free as mem: %d", disk_p->type);
  }

  // Free both the data storage and the object itself
  free(disk_p->data_p);
  free(disk_p);

  return;
}

/////////////////////////////////////////////////////////////////////
// Buffer Layer
/////////////////////////////////////////////////////////////////////

#define MAX_BUFFER 16

typedef struct Buffer_t {
  Storage *disk_p;
  // These two are status bit for the buffer
  uint64_t in_use : 1;
  uint64_t dirty  : 1;
  Buffer_t *next_p;
  Buffer_t *prev_p;
  // This holds the buffer data
  uint8_t data[DEFAULT_SECTOR_SIZE];
} Buffer;

// Static object
Buffer buffers[MAX_BUFFER];

// These two maintain a linked list of valid buffer objects
Buffer *buffer_head_p = NULL;
Buffer *buffer_tail_p = NULL;

/*
 * init_buffer() - This function initializes the environment for buffers
 */
void init_buffer() {
  for(int i = 0;i < MAX_BUFFER;i++) {
    memset(buffers + i, 0x00, sizeof(Buffer));
  }

  return;
}

/*
 * buffer_add_to_head() - Adds a buffer object to the head of the queue
 */
void buffer_add_to_head(Buffer *buffer_p) {
  if(buffer_head_p == NULL) {
    assert(buffer_tail_p == NULL);
    buffer_head_p = buffer_tail_p = buffer_p;
    buffer_p->next_p = buffer_p->prev_p = NULL;
  } else {
    buffer_head_p->prev_p = buffer_p;
    buffer_p->next_p = buffer_head_p;
    buffer_p->prev_p = NULL;
    buffer_head_p = buffer_p;
  }

  return;
}

/**/
void buffer_remove(Buffer *buffer_p) {

}

/////////////////////////////////////////////////////////////////////
// FS Layer
/////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////
// Test Cases
/////////////////////////////////////////////////////////////////////

#define DEBUG
#ifdef DEBUG

void test_lba_rw(Storage *disk_p) {
  uint8_t buffer[DEFAULT_SECTOR_SIZE];
  for(size_t i = 0;i < disk_p->sector_count;i++) {
    memset(buffer, (char)i, DEFAULT_SECTOR_SIZE);
    disk_p->write(disk_p, i, buffer);
  }

  for(size_t i = 0;i < disk_p->sector_count;i++) {
    disk_p->read(disk_p, i, buffer);
    for(int j = 0;j < DEFAULT_SECTOR_SIZE;j++) {
      if(buffer[j] != (uint8_t)i) {
        fatal_error("LBA read fail (i = %lu, j = %d)", i, j);
      }
    }
  }

  return;
}

int main() {
  Storage *disk_p = get_mem_storage(2880);
  test_lba_rw(disk_p);
  free_mem_storage(disk_p);
  return 0;
}
#else 

/////////////////////////////////////////////////////////////////////
// Main Function
/////////////////////////////////////////////////////////////////////

int main() {
  return 0;
}

#endif

