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
  // This is the LBA of the buffer object
  uint64_t lba;
  struct Buffer_t *next_p;
  struct Buffer_t *prev_p;
  // This holds the buffer data
  uint8_t data[DEFAULT_SECTOR_SIZE];
} Buffer;

// Static object
Buffer buffers[MAX_BUFFER];
// Number of buffers that is still in-use
size_t buffer_in_use = 0;

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

  buffer_head_p = buffer_tail_p = NULL;
  buffer_in_use = 0;

  return;
}

/*
 * buffer_add_to_head() - Adds a buffer object to the head of the queue
 */
void buffer_add_to_head(Buffer *buffer_p) {
  assert(buffer_p != NULL);
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

  buffer_in_use++;

  return;
}

/*
 * buffer_remove() - This function removes a buffer from the linked list
 */
void buffer_remove(Buffer *buffer_p) {
  assert(buffer_p != NULL);
  assert(buffer_p->in_use == 1);
  // If there is only one element in the buffer, then we just
  // set head and tail to NULL
  if(buffer_head_p == buffer_tail_p) {
    assert(buffer_p == buffer_head_p);
    buffer_head_p = buffer_tail_p = NULL;
  } else if(buffer_head_p == buffer_p) {
    // If the buffer we remove is at the head
    buffer_head_p = buffer_head_p->next_p;
    buffer_head_p->prev_p = NULL;
  } else if(buffer_tail_p == buffer_p) {
    buffer_tail_p = buffer_tail_p->prev_p;
    buffer_tail_p->next_p = NULL;
  } else {
    Buffer *next_p = buffer_p->next_p;
    Buffer *prev_p = buffer_p->prev_p;
    prev_p->next_p = next_p;
    next_p->prev_p = prev_p;
  }

  buffer_in_use--;

  return;
}

/*
 * buffer_access() - Move a buffer object to the head of the linked list
 */
void buffer_access(Buffer *buffer_p) {
  buffer_remove(buffer_p);
  buffer_add_to_head(buffer_p);

  return;
}

#define BUFFER_WB_DEBUG

/*
 * buffer_wb() - This function writes back the buffer if it is dirty, or 
 *               simply clear it
 * 
 * Note that we do not remove the buffer from the linked list
 */
void buffer_wb(Buffer *buffer_p, Storage *disk_p) {
  assert(buffer_p->in_use == 1);
  if(buffer_p->dirty == 1) {
    disk_p->write(disk_p, buffer_p->lba, buffer_p->data);
#ifdef BUFFER_WB_DEBUG
    info("Writing back buffer %lu (LBA %lu)", 
        (size_t)(buffer_p - buffers),
        buffer_p->lba);
#endif
  }
  
  return;
}

#define BUFFER_FLUSH_DEBUG

/*
 * buffer_flush() - This function removes the buffer from the linked list
 *                  and then writes back if it is dirty
 * 
 * We also clear the in_use and dirty flag for the buffer
 */
void buffer_flush(Buffer *buffer_p, Storage *disk_p) {
  assert(buffer_p->in_use == 1);
#ifdef BUFFER_FLUSH_DEBUG
  info("Flushing buffer %lu (LBA %lu)", 
       (size_t)(buffer_p - buffers),
       buffer_p->lba);
#endif
  buffer_remove(buffer_p);
  buffer_wb(buffer_p, disk_p);
  buffer_p->in_use = 0;
  buffer_p->dirty = 0;

  return;
}

/*
 * buffer_evict_lru() - Evicts a buffer using LRU
 * 
 * Since we move the buffer object to the head of the linked list for 
 * every reference, in order to implement LRU we simply remove and write back
 * the last buffer in the linked list
 * 
 * Note that the buffer will also be removed from the linked list
 * 
 * We return the evicted buffer from this function for the caller to make
 * use of it. The returned buffer has its in_use and dirty flag cleared
 */
Buffer *buffer_evict_lru(Storage *disk_p) {
  assert(buffer_head_p != NULL && buffer_tail_p != NULL);
  // We just take the tail and remove it and then write back
  Buffer *buffer_p = buffer_tail_p;
  buffer_flush(buffer_p, disk_p);

  return buffer_p;
}

/*
 * get_empty_buffer() - Returns an empty buffer that we could use to hold data
 * 
 * This function searches the buffer slots, and tries to find an empty buffer.
 * If none is found, then we evict a buffer that is in-use, and return it
 * 
 * The returned buffer always have in_use set to 1 and dirty set to 0
 */
Buffer *get_empty_buffer(Storage *disk_p) {
  // We set this if we have found one
  Buffer *buffer_p = NULL;

  // If the buffer pool still has at least one buffer
  if(buffer_in_use != MAX_BUFFER) {
    // First find in the buffer array
    for(int i = 0;i < MAX_BUFFER;i++) {
      if(buffers[i].in_use == 0) {
        // Make it in use and clean
        buffers[i].in_use = 1;
        buffers[i].dirty = 0;
        buffer_p = buffers + i;
        break;
      }
    }
  }

  // If did not find any buffer in the array then all buffers are
  // in use, in which case we just search the linked list
  if(buffer_p == NULL) {
    // The buffer has been removed from the linked list
    buffer_p = buffer_evict_lru(disk_p);
    assert(buffer_p->in_use == 0 && buffer_p->dirty == 0);
    buffer_p->in_use = 1;
  }

  // Then put the buffer back into the linked list
  buffer_add_to_head(buffer_p);

  return buffer_p;
}

/*
 * buffer_print() - This function prints the buffers in-use from the head to
 *                  the tail of the linked list
 */
void buffer_print() {
  Buffer *buffer_p = buffer_head_p;
  // For empty buffers, just print a line and exit
  if(buffer_p == NULL) {
    info("(Empty buffer)");
  } else {
    while(buffer_p != NULL) {
      fprintf(stderr, "%lu,%lu(%X) ", 
              buffer_p - buffers,
              buffer_p->lba, 
              (uint32_t)((buffer_p->dirty << 1) | (buffer_p->in_use)));
      buffer_p = buffer_p->next_p;
    }
  }

  // Print a new line
  info("");

  return;
}

/*
 * _read_lba()
 * read_lba() - This function reads the sector of the given LBA
 * 
 * We return a pointer to the read data. If the data is already in the 
 * buffer, then no read happens, and we just return the buffer's data area.
 * Otherwise we allocate a new buffer, and read data, and return the pointer.
 * 
 * This function is a wrapper to the read read_lba() where it returns the 
 * buffer, and the read_lba() returns a pointer
 */
Buffer *_read_lba(Storage *disk_p, uint64_t lba) {
  Buffer *buffer_p = buffer_head_p;
  while(buffer_p != NULL) {
    // If the LBA is in the buffer, then we just return its data
    if(buffer_p->lba == lba) {
      assert(buffer_p->in_use == 1);
      buffer_access(buffer_p);
      break;
    }

    buffer_p = buffer_p->next_p;
  }

  if(buffer_p == NULL) {
    // If there is no buffered content we have to allocate one
    buffer_p = get_empty_buffer(disk_p);
    assert(buffer_p->in_use == 1);
    buffer_p->lba = lba;
  
    // Perform read here and return the pointer
    disk_p->read(disk_p, lba, buffer_p->data);
  }

  return buffer_p;
}

uint8_t *read_lba(Storage *disk_p, uint64_t lba) {
  return _read_lba(disk_p, lba)->data;
}

/*
 * read_lba_for_write() - This function reads an LBA for performing 
 *                        write operations
 * 
 * If the LBA is already in the buffer, we simply set its dirty flag. Otherwise
 * the buffer will first be loaded into the buffer, and then be marked as dirty
 */
uint8_t *read_lba_for_write(Storage *disk_p, uint64_t lba) {
  Buffer *buffer_p = _read_lba(disk_p, lba);
  buffer_p->dirty = 1;

  return buffer_p->data;
}

/////////////////////////////////////////////////////////////////////
// FS Layer
/////////////////////////////////////////////////////////////////////

// This is the length of the free array
#define FREE_ARRAY_MAX 100

typedef struct {
  // Number of elements in the local array
  uint16_t nfree;
  // The first word of this structure is the block number
  // to the next block that holds this list
  // All elements after the first one is the free blocks
  uint16_t free[FREE_ARRAY_MAX];
} __attribute__((packed)) FreeArray;

// This defines the first block of the file system
typedef struct {
  // Number of sectors for i-node
  uint16_t isize;
  // Number of sectors for file storage
  uint16_t fsize;
  // Linked list of free blocks and the free array
  FreeArray free_array;
  // Number of free inodes as a fast cache in the following
  // array
  uint16_t ninode;
  uint16_t inode[FREE_ARRAY_MAX];
  char flock;
  char ilock;
  char fmod;
  uint16_t time[2];
} __attribute__((packed)) SuperBlock;

/////////////////////////////////////////////////////////////////////
// Test Cases
/////////////////////////////////////////////////////////////////////

#define DEBUG
#ifdef DEBUG

void test_lba_rw(Storage *disk_p) {
  info("Testing LBA r/w...");
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

void test_buffer(Storage *disk_p) {
  info("Testing buffer...");
  for(int i = 0;i < MAX_BUFFER * 2;i++) {
    void *p = read_lba(disk_p, (uint64_t)i);
    memset(p, (char)i, disk_p->sector_size);

    buffer_print();
  }
  
  info("Testing buffer and dirty flag...");
  for(int i = 0;i < MAX_BUFFER * 2;i++) {
    void *p = read_lba_for_write(disk_p, (uint64_t)i);
    memset(p, (char)i, disk_p->sector_size);

    buffer_print();
  }

  return;
}

int main() {
  init_buffer();
  Storage *disk_p = get_mem_storage(2880);
  test_lba_rw(disk_p);
  test_buffer(disk_p);
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

