/*
 * ofs.c - A file for simulating the UNIX SYSTEM V Old File System
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <assert.h>
#include <time.h>
#include <stdlib.h>

// If word length is 4 then we use 32 bit inode and sector
#define WORD_SIZE 2

#if WORD_SIZE == 4
#define DEFAULT_SECTOR_SIZE 4096
#else
#define DEFAULT_SECTOR_SIZE 512
#endif

// If we simulate IO delay, then this is the # of ms
// each IO operation will have
#define IO_OVERHEAD_MS 2
//#define SIMULATE_IO

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

#ifdef SIMULATE_IO
  struct timespec ts;
  ts.tv_sec = IO_OVERHEAD_MS / 1000;
  ts.tv_nsec = (IO_OVERHEAD_MS % 1000) * 1000000;
  nanosleep(&ts, NULL);
#endif

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

#ifdef SIMULATE_IO
  struct timespec ts;
  ts.tv_sec = IO_OVERHEAD_MS / 1000;
  ts.tv_nsec = (IO_OVERHEAD_MS % 1000) * 1000000;
  nanosleep(&ts, NULL);
#endif

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
  // This is number of pins the buffer has seen
  uint64_t pinned_count;
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
 * buffer_init() - This function initializes the environment for buffers
 */
void buffer_init() {
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

//#define BUFFER_WB_DEBUG

/*
 * buffer_wb() - This function writes back the buffer if it is dirty, or 
 *               simply clear it
 * 
 * Note that we do not remove the buffer from the linked list. But this function
 * clears the dirty bit of the buffer object
 */
void buffer_wb(Buffer *buffer_p, Storage *disk_p) {
  assert(buffer_p->in_use == 1);
  if(buffer_p->dirty == 1) {
    disk_p->write(disk_p, buffer_p->lba, buffer_p->data);
    buffer_p->dirty = 0;
#ifdef BUFFER_WB_DEBUG
    info("Writing back buffer %lu (LBA %lu)", 
        (size_t)(buffer_p - buffers),
        buffer_p->lba);
#endif
  }
  
  return;
}

/*
 * buffer_find_using_data() - This function returns the corresponding buffer
 *                            given the data pointer into the buffer's data
 *
 * Note that the data pointer can be anywhere inside the data area. We search
 * all the buffer, including those not in-use
 */
Buffer *buffer_find_using_data(Storage *disk_p, const void *data_p) {
  for(int i = 0;i < MAX_BUFFER;i++) {
    if((uint8_t *)data_p >= buffers[i].data && 
       (uint8_t *)data_p < buffers[i].data + disk_p->sector_size) {
      return buffers + i;
    }
  }

  return NULL;
}

/*
 * buffer_set_dirty() - This function sets the buffer to dirty using its data
 *                      area pointer
 */
void buffer_set_dirty(Storage *disk_p, const void *data_p) {
  Buffer *buffer_p = buffer_find_using_data(disk_p, data_p);
  if(buffer_p == NULL) {
    fatal_error("Data pointer out of buffer's reach (set dirty)");
  } else if(buffer_p->in_use == 0) {
    fatal_error("Could not set an unused buffer as dirty");
  }

  buffer_p->dirty = 1;

  return;
}

/*
 * buffer_is_dirty() - Returns 1 if the buffer the pointer point to is dirty
 */
int buffer_is_dirty(Storage *disk_p, const void *data_p) {
  Buffer *buffer_p = buffer_find_using_data(disk_p, data_p);
  if(buffer_p == NULL) {
    fatal_error("Data pointer out of buffer's reach (is_dirty)");
  } else if(buffer_p->in_use == 0) {
    fatal_error("Could not check an unused buffer as dirty");
  }

  return !!(buffer_p->dirty != 0);
}

/*
 * buffer_pin() - This function accepts a buffer's data pointer and pins 
 *                the buffer
 *
 * The data pointer can be anywhere inside a buffer's data area. If the 
 * buffer is not currently in-use then we error. Also reports error when
 * the buffer is pinned
 */
void buffer_pin(Storage *disk_p, const void *data_p) {
  // Find the buffer first
  Buffer *buffer_p = buffer_find_using_data(disk_p, data_p);
  if(buffer_p == NULL) {
    fatal_error("Data pointer out of buffer's reach (pin)");
  } else if(buffer_p->in_use == 0) {
    fatal_error("Could not pin an unused buffer");
  }

  buffer_p->pinned_count++;

  return;
}

/*
 * buffer_unpin() - This function unpins a buffer. 
 *
 * The error condition is the same as buffer_pin(), except that it reports error
 * when the buffer is already unpinned.
 */
void buffer_unpin(Storage *disk_p, const void *data_p) {
  Buffer *buffer_p = buffer_find_using_data(disk_p, data_p);
  if(buffer_p == NULL) {
    fatal_error("Data pointer out of buffer's reach (unpin)");
  } else if(buffer_p->in_use == 0) {
    fatal_error("Could not unpin an unused buffer");
  }

  // Cannot unpin a buffer if it is not pinned
  assert(buffer_p->pinned_count != 0);
  buffer_p->pinned_count--;

  return;
}

/*
 * buffer_is_pinned() - This function checks whether the buffer is pinned
 *
 * Return 1 if yes, 0 if not
 */
int buffer_is_pinned(Storage *disk_p, const void *data_p) {
  Buffer *buffer_p = buffer_find_using_data(disk_p, data_p);
  if(buffer_p == NULL) {
    fatal_error("Data pointer out of buffer's reach (is_pinned)");
  } else if(buffer_p->in_use == 0) {
    fatal_error("Could not check an unused buffer");
  }

  return !!(buffer_p->pinned_count != 0);
}

//#define BUFFER_FLUSH_DEBUG

/*
 * buffer_flush() - This function removes the buffer from the linked list
 *                  and then writes back if it is dirty
 * 
 * We also clear the in_use and dirty flag for the buffer
 *
 * Note that we could not flush a pinned buffer, because it might be still 
 * in-use
 */
void buffer_flush(Buffer *buffer_p, Storage *disk_p) {
  assert(buffer_p->in_use == 1);
  assert(buffer_p->pinned_count == 0);
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
 * buffer_flush_all() - This function flushes all buffers and writes back
 *                      those that are still dirty
 *
 * Note that if there is any buffer that is still pinned, then this function
 * would fail
 */
void buffer_flush_all(Storage *disk_p) {
  while(buffer_head_p != NULL) {
    assert(buffer_head_p->pinned_count == 0);
    buffer_flush(buffer_head_p, disk_p);
  }

  return;
}

/*
 * buffer_flush_all_no_rm() - This function writes back all dirty buffers
 *                            but does not remove them from the linked list
 */
void buffer_flush_all_no_rm(Storage *disk_p) {
  Buffer *buffer_p = buffer_head_p;
  while(buffer_p != NULL) {
    // Write it back without removing it from the linked list
    // Also this function will clear the dirty flag
    buffer_wb(buffer_p, disk_p);
    buffer_p = buffer_p->next_p;
  }

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
 *
 * We do not remove pinned buffers. Instead, we start from the tail of the
 * linked list, and iterate towards the head. If we could not find any unpinned
 * buffer, then this function fails (i.e. the working set of the fs should not
 * exceed the buffer pool size)
 */
Buffer *buffer_evict_lru(Storage *disk_p) {
  assert(buffer_head_p != NULL && buffer_tail_p != NULL);
  // We just take the tail and remove it and then write back
  Buffer *buffer_p = buffer_tail_p;
  // Go forward until we find an unpinned buffer
  while(buffer_p->pinned_count != 0) {
    buffer_p = buffer_p->prev_p;
    if(buffer_p == NULL) {
      fatal_error("All buffers are pinned; could not evict");
    }
  }
  
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
    assert(buffer_p->in_use == 0 && 
           buffer_p->dirty == 0 && 
           buffer_p->pinned_count == 0);
    buffer_p->in_use = 1;
  }

  // Then put the buffer back into the linked list
  buffer_add_to_head(buffer_p);

  return buffer_p;
}

/*
 * buffer_count_pinned() - This function counts the number of pinned buffers
 */
size_t buffer_count_pinned() {
  size_t count = 0UL;
  for(int i = 0;i < MAX_BUFFER;i++) {
    if(buffers[i].pinned_count != 0) {
      count++;
    }
  }

  return count;
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
              (uint32_t)((!!(buffer_p->pinned_count != 0) << 2) | 
                         (buffer_p->dirty << 1) | 
                         (buffer_p->in_use)));
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
 *
 * The read_flag determines whether we perform read operation if the LBA
 * is not buffered. Because sometimes we just want to perform blind write.
 */
Buffer *_read_lba(Storage *disk_p, uint64_t lba, int read_flag) {
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
    // If we do not perform read then we will do blind write
    if(read_flag == 1) {
      disk_p->read(disk_p, lba, buffer_p->data);
    }
  }

  return buffer_p;
}

uint8_t *read_lba(Storage *disk_p, uint64_t lba) {
  return _read_lba(disk_p, lba, 1)->data;
}

/*
 * read_lba_for_write() - This function reads an LBA for performing 
 *                        write operations
 * 
 * If the LBA is already in the buffer, we simply set its dirty flag. Otherwise
 * the buffer will first be loaded into the buffer, and then be marked as dirty
 */
uint8_t *read_lba_for_write(Storage *disk_p, uint64_t lba) {
  Buffer *buffer_p = _read_lba(disk_p, lba, 1);
  buffer_p->dirty = 1;

  return buffer_p->data;
}

/*
 * write_lba() - This function creases a buffer of the given LBA
 *               and buffers user's writes into the sector
 *
 * The sector will eventually reach the disk when it is written back
 */
uint8_t *write_lba(Storage *disk_p, uint64_t lba) {
  // NOTE: Pass 0 here to avoid reading the sector
  Buffer *buffer_p = _read_lba(disk_p, lba, 0);
  buffer_p->dirty = 1;

  return buffer_p->data;
}

/////////////////////////////////////////////////////////////////////
// FS Layer
/////////////////////////////////////////////////////////////////////

// User error definitions

#define FS_SUCCESS           0
// File name too long
#define FS_ERR_NAME_TOO_LONG 1
// Invalid character in file name
#define FS_ERR_ILLEGAL_CHAR  2
// Invalid file name (characters are valid)
#define FS_ERR_ILLEGAL_NAME  3
// Run out of sectors
#define FS_ERR_NO_SPACE      4
// Run out of inodes
#define FS_ERR_NO_INODE      5

#if WORD_SIZE == 4
typedef uint32_t sector_t;
typedef sector_t sector_count_t;
// Inode ID type
typedef uint32_t inode_id_t;
typedef inode_id_t inode_count_t;

typedef uint32_t dir_count_t;

typedef uint32_t word_t;
typedef uint16_t halfword_t;
#else
typedef uint16_t sector_t;
typedef sector_t sector_count_t;
// Inode ID type
typedef uint16_t inode_id_t;
typedef inode_id_t inode_count_t;

typedef uint16_t dir_count_t;

typedef uint16_t word_t;
typedef uint8_t halfword_t;
#endif
// Sector type


// This is the length of the free array
#define FS_FREE_ARRAY_MAX 100
#define FS_SIG_SIZE 4
#define FS_SIG "WZQ"
// This is the sector ID of the super block
#define FS_SB_SECTOR 1
// This indicates invalid sector numbers
#define FS_INVALID_SECTOR 0
// Since inode #0 is a valid one, we define invalid inode to be -1
#define FS_INVALID_INODE  ((sector_t)-1)
// Root inode is the first inode in the system
#define FS_ROOT_INODE 0

typedef struct {
  // Number of elements in the local array
  sector_count_t nfree;
  // The first word of this structure is the block number
  // to the next block that holds this list
  // All elements after the first one is the free blocks
  sector_t       free[FS_FREE_ARRAY_MAX];
} __attribute__((packed)) FreeArray;

// This defines the first block of the file system
typedef struct {
  // We use this to identify a valid super block
  char signature[FS_SIG_SIZE];
  // Number of sectors for i-node
  sector_t isize;
  // Number of sectors for file storage
  // NOTE: We modified the semantics of this field.
  // In the original OFS design this is the absolute number of blocks
  // used by the FS and the bootsect. We make it relative to the inode
  // blocks
  sector_t fsize;
  // Linked list of free blocks and the free array
  FreeArray free_array;
  // Number of free inodes as a fast cache in the following
  // array
  inode_count_t ninode;
  inode_id_t    inode[FS_FREE_ARRAY_MAX];
  // These are used as flags
  halfword_t flock;
  halfword_t ilock;
  halfword_t fmod;
  word_t time[2];
} __attribute__((packed)) SuperBlock;

#define FS_ADDR_ARRAY_MAX 8

// This defines the inode structure
typedef struct {
  word_t flags;
  // Number of hardlinks to the file
  halfword_t nlinks;
  // User ID and group ID
  halfword_t uid;
  halfword_t gid;
  // High bits of the size field
  // Note that this may not be used
  halfword_t size0;
  // Low bits of the size field
  word_t size1;
  sector_t addr[FS_ADDR_ARRAY_MAX];
  // Access time
  word_t actime[2];
  // Modification time
  word_t modtime[2];
} __attribute__((packed)) Inode;

#if WORD_SIZE != 4
#define FS_DIR_ENTRY_NAME_MAX 14
#else
#define FS_DIR_ENTRY_NAME_MAX 28
#endif

// This defines the directory structure
typedef struct {
  // The inode number this directory entry represents
  // Use FS_INVALID_INODE to indicate that the entry is free
  inode_id_t inode;
  // Note that file names are not required to terminate with 0x0
  // but this field is null-padded
  char name[FS_DIR_ENTRY_NAME_MAX];
} DirEntry;

// This is the in-memory representation of the file system metadata
// We load the super block and initialize this object
// Once initialized it is never changed for the same fs
typedef struct {
  sector_t sb_sector;
  sector_t inode_start_sector;
  sector_t inode_end_sector;
  sector_count_t inode_sector_count;
  sector_t free_start_sector;
  sector_t free_end_sector;
  sector_count_t free_sector_count;
  sector_count_t total_sector_count;
  inode_count_t total_inode_count;
  inode_count_t inode_per_sector;
  // Number of sector IDs per indirection sector
  sector_count_t id_per_indir_sector;
  // The start sector for extra large blocks
  sector_t extra_large_start_sector;
  dir_count_t dir_per_sector;
  
} Context;

// This is the content of the fs
Context context;

// Next we define flags for inode flags word
#define FS_INODE_IN_USE      0x8000
// The following are file type code. We should mask off other bits
// to test which type they belong to
#define FS_INODE_TYPE_DIR    0x4000
#define FS_INODE_TYPE_CHAR   0x2000
#define FS_INODE_TYPE_BLOCK  0x6000
#define FS_INODE_TYPE_FILE   0x0000
// Use this mask to extract the inode type
#define FS_INODE_TYPE_MASK   0x6000
#define FS_INODE_TYPE_SHIFT_BITS 13
// Whether the file is a large file
#define FS_INODE_LARGE       0x1000
#define FS_INODE_SET_UID     0x0800
#define FS_INODE_SET_GID     0x0400
// Note that there is a gap
#define FS_INODE_OWNER_READ  0x0100
#define FS_INODE_OWNER_WRITE 0x0080
#define FS_INODE_OWNER_EXEC  0x0040
#define FS_INODE_GROUP_READ  0x0020
#define FS_INODE_GROUP_WRITE 0x0010
#define FS_INODE_GROUP_EXEC  0x0008
#define FS_INODE_OTHER_READ  0x0004
#define FS_INODE_OTHER_WRITE 0x0002
#define FS_INODE_OTHER_EXEC  0x0001

sector_t fs_alloc_sector(Storage *disk_p);
Inode *fs_load_inode_sector(Storage *disk_p, inode_id_t inode, int write_flag);

/*
 * fs_load_context() - This function loads the context object using the super block
 *
 * For each file system mounted, this can only be done once, and then used
 * for the entire session
 *
 * This function should only be called after the fs has been initialized or 
 * mounted.
 */
void fs_load_context(Storage *disk_p) {
  // Load the super block in read-only mode
  SuperBlock *sb_p = (SuperBlock *)read_lba(disk_p, FS_SB_SECTOR);

  context.sb_sector = FS_SB_SECTOR;
  context.inode_start_sector = FS_SB_SECTOR + 1;
  context.inode_end_sector = FS_SB_SECTOR + 1 + sb_p->isize;
  context.inode_sector_count = sb_p->isize;
  context.free_start_sector = context.inode_end_sector;
  context.free_end_sector = context.free_start_sector + sb_p->fsize;
  context.free_sector_count = sb_p->fsize;
  context.total_sector_count = \
    context.free_start_sector + context.free_sector_count;
  // This is the number of inodes per sector
  context.inode_per_sector = disk_p->sector_size / sizeof(Inode);
  // Total number of inodes in the system
  context.total_inode_count = \
    context.inode_per_sector * context.inode_sector_count;
  
  // These two are used for computing the sector ID of a given offset
  context.id_per_indir_sector = disk_p->sector_size / sizeof(sector_t);
  context.extra_large_start_sector = \
    context.id_per_indir_sector * (FS_ADDR_ARRAY_MAX - 1);
  
  // This is the number of directory entries per sector
  context.dir_per_sector = disk_p->sector_size / sizeof(DirEntry);

  return;
}

/*
 * fs_reset_addr() - This function resets the addr array of a given inode
 */
void fs_reset_addr(Inode *inode_p) {
  for(int i = 0;i < FS_ADDR_ARRAY_MAX;i++) {
    inode_p->addr[i] = FS_INVALID_SECTOR;
  }

  return;
}

/*
 * fs_init_inode() - This function initializes the inode from a given sector
 *                   of the storage
 *
 * The function also returns the number of sectors the inode array occupies
 * to initialize data sectors.
 */
size_t fs_init_inode(Storage *disk_p, 
                     size_t inode_start, 
                     size_t total_end) {
  size_t current_inode = inode_start;
  // Number of inodes in each sector
  // This should be an integer
  const size_t inode_per_sector = disk_p->sector_size / sizeof(Inode);
  info("  # of inodes per sector: %lu", inode_per_sector);  
  // We stop initializing inode when we could allocate one inode for
  // each sector
  while(total_end > current_inode) {
    void *data = write_lba(disk_p, current_inode);
    memset(data, 0x00, disk_p->sector_size);

    // Reset the addr array (we may use an arbitrary value for invalid sector,
    // so setting it to 0x00 may not be sufficient)
    Inode *inode_p = (Inode *)data;
    for(int i = 0;i < inode_per_sector;i++) {
      fs_reset_addr(inode_p + i);
    }

    // Go to the next inode sector
    current_inode++;
    // We have allocated inode for each of the blocks in this range
    total_end -= inode_per_sector;
  }

  // Flush all inode sectors
  buffer_flush_all_no_rm(disk_p);

  // Number of inodes
  return current_inode - inode_start;
}

/*
 * fs_init_free_list() - This function builds the free list
 *
 * The free list consists of 99 elements, which are free block numbers,
 * and 1 pointer to the next free block. Note that sectors that hold the 
 * free list themselves could not occur in the free list, and therefore,
 * we begin allocating sectors from the last sector of the entire fs
 */
size_t fs_init_free_list(Storage *disk_p, size_t free_start, size_t free_end) {
  size_t current_free = free_start;
  while(free_end > current_free) {
    sector_t *data = (sector_t *)write_lba(disk_p, current_free);
    // There must be at least one free sector
    assert(free_end > (current_free + 1));
    // current_free should not be counted as a free block
    size_t delta = free_end - (current_free + 1);
    // These two are default values
    sector_t next_free_list = current_free + 1;
    sector_t free_sector_count = FS_FREE_ARRAY_MAX - 1;
    // We do not need more free blocks, the current one is the 
    // last one
    if(delta <= free_sector_count) {
      // There is no "next" block, set it to 0
      next_free_list = FS_INVALID_SECTOR;
      free_sector_count = delta;
    }

    // Do not allow empty list
    assert(free_sector_count != 0);
    FreeArray *free_array_p = (FreeArray *)data;
    // It does not include the first element which is the next sector ID
    free_array_p->nfree = free_sector_count;
    free_array_p->free[0] = next_free_list;
    for(int i = 0;i < free_sector_count;i++) {
      free_end--;
      // This is the current last free sector
      free_array_p->free[i + 1] = free_end;
    }

    // Go to next free block
    current_free++;
  }

  buffer_flush_all_no_rm(disk_p);

  return current_free - free_start;
}

/*
 * fs_get_file_size() - This function returns the size of an inode's file
 */
size_t fs_get_file_size(const Inode *inode_p) {
  // Note that we must first convert it to size_t and then shift
  // Otherwise we will just get 0
  return ((size_t)inode_p->size0 << (sizeof(word_t) * 8)) + \
         (size_t)inode_p->size1;
}

/*
 * fs_set_file_size() - This function sets the file size field for 
 *                      an inode
 */
void fs_set_file_size(Inode *inode_p, size_t sz) {
  inode_p->size1 = (word_t)sz;
  // Note that we need to shift first and then convert
  inode_p->size0 = (halfword_t)(sz >> (8 * sizeof(word_t)));
  return;
}

/*
 * fs_set_file_type() - This function sets the type of the file
 */
void fs_set_file_type(Inode *inode_p, word_t type) {
  // The type must be 0b00, 0b01, 0b10 or 0b11
  assert(type == FS_INODE_TYPE_BLOCK ||
         type == FS_INODE_TYPE_CHAR ||
         type == FS_INODE_TYPE_FILE ||
         type == FS_INODE_TYPE_DIR);
  // First clear the bits, and then apply the type
  inode_p->flags &= (~(FS_INODE_TYPE_MASK));
  inode_p->flags |= type;

  return;
}

/*
 * fs_get_file_type() - This function returns the file type
 *
 * The returned type is one of the following:
 *   FS_INODE_TYPE_BLOCK, FS_INODE_TYPE_CHAR, FS_INODE_TYPE_FILE, 
 *   FS_INODE_TYPE_DIR
 */
word_t fs_get_file_type(const Inode *inode_p) {
  return inode_p->flags & FS_INODE_TYPE_MASK;
}

/*
 * fs_is_file_large() - Returns 1 if the file is large. 0 if not
 */
int fs_is_file_large(const Inode *inode_p) {
  // We need to convert the mask into 0 or 1
  return !!(inode_p->flags & FS_INODE_LARGE);
}

/*
 * fs_set_file_large() - Sets the large flag for the file
 */
void fs_set_file_large(Inode *inode_p) {
  inode_p->flags |= FS_INODE_LARGE;
  return;
}

/*
 * fs_is_file_extra_large() - Returns 1 if the file is extra large
 *
 * We determine whether a file is extra large using two sub-conditions:
 *   1. The file has large bit set
 *   2. The file has a valid sector number on addr[7]
 */
int fs_is_file_extra_large(const Inode *inode_p) {
  return !!(fs_is_file_large(inode_p) && \
            inode_p->addr[FS_ADDR_ARRAY_MAX - 1] != FS_INVALID_SECTOR);
}
 
/*
 * fs_get_file_sector() - This function returns the sector ID given an offset in
 *                        the file
 *
 * This function returns invalid sector ID if the offset falls in a region
 * that no data has been written. By default this should map to all-zero sector
 *
 * This function is for read. It does not allocate any sector or change the 
 * layout of the inode's addr list.
 *
 * This function pins the inode passed in, such that its buffer remains valid
 * after return
 */
sector_t fs_get_file_sector(Storage *disk_p, 
                            const Inode *inode_p, 
                            size_t offset) {
  buffer_pin(disk_p, inode_p);

  // This is the linear ID in the file. Note that we can only address 16 bit
  // sector size
  sector_t sector = (sector_t)(offset / disk_p->sector_size);
  // Make sure we did not overflow sector_t
  assert(((size_t)sector * disk_p->sector_size) == offset);
  sector_t ret;
  // If the file is small, then the sector ID must be less than 8
  if(fs_is_file_large(inode_p) == 0) {
    assert(sector < FS_ADDR_ARRAY_MAX);
    // This could be invalid sector
    ret = inode_p->addr[sector];
  } else {
    // Number of IDs inside an indirection sector
    sector_t indir_index = sector / context.id_per_indir_sector;
    sector_t indir_offset = sector % context.id_per_indir_sector;
    
    // Then if the file is large file, and the index is not the last one
    // then we know we can always use the indirection sector
    if(indir_index < (FS_ADDR_ARRAY_MAX - 1)) {
      sector_t indir_sector = inode_p->addr[indir_index];
      // If the sector does not exist, then we assume the range it covers 
      // contains all zero, and just return invalid
      if(indir_sector == FS_INVALID_SECTOR) {
        ret = FS_INVALID_SECTOR;
      } else {
        sector_t *data_p = (sector_t *)read_lba(disk_p, indir_sector);
        ret = data_p[indir_offset]; 
      }
    } else if(fs_is_file_extra_large(inode_p) == 0) {
      // If the offset implies that the file should be extra large
      // but actually the file is not extra large, we return invalid
      // sector because there is no way to find the correct sector
      ret = FS_INVALID_SECTOR;
    } else {
      assert(sector >= context.extra_large_start_sector);
      // This branch handles extra large file
      // This is the address of the first indirection sector
      const sector_t first_indir_sector = \
        inode_p->addr[FS_ADDR_ARRAY_MAX - 1];
      // Starts with 0 in the extra large area
      sector -= context.extra_large_start_sector;
      // Just treat it as another array of indir sector
      indir_index = sector / context.id_per_indir_sector;
      // It could not overflow the first indirection sector
      assert(indir_index < context.id_per_indir_sector);
      indir_offset = sector % context.id_per_indir_sector;
      sector_t *data_p = (sector_t *)read_lba(disk_p, first_indir_sector);
      sector_t second_indir_sector = data_p[indir_index];
      if(second_indir_sector == FS_INVALID_SECTOR) {
        ret = FS_INVALID_SECTOR;
      } else {
        sector_t *data_p = (sector_t *)read_lba(disk_p, second_indir_sector);
        ret = data_p[indir_offset];
      }
    }
  }

  buffer_unpin(disk_p, inode_p);
  return ret;
}

/*
 * fs_convert_to_large() - Converts a given inode to large file and changes the
 *                         inode addr layout accordingly
 *
 * The inode passed in must not be an inode itself. If this function fails 
 * for lacking free sector, we return INVALID_SECTOR; otherwise return the
 * sector for new indir sector.
 *
 * This function does not logically change the file
 *
 * inode_p should be pinned as we read another sector
 */
sector_t fs_convert_to_large(Storage *disk_p, Inode *inode_p) {
  assert(fs_is_file_large(inode_p) == 0);
  assert(buffer_is_pinned(disk_p, inode_p) == 1);

  sector_t ret;
  // First use an indirection sector to hold all pointers
  sector_t indir_sector = fs_alloc_sector(disk_p);
  // If allocation fail we return fail
  if(indir_sector == FS_INVALID_SECTOR) {
    ret = FS_INVALID_SECTOR;
  } else {
    ret = indir_sector;
    // Copy the addr array into the indir sector
    sector_t *data_p = (sector_t *)write_lba(disk_p, indir_sector);
    // Fill the entire disk with INVALID SECTOR
    for(int i = 0;i < context.id_per_indir_sector;i++) {
      data_p[i] = FS_INVALID_SECTOR;
    }
    memcpy(data_p, inode_p->addr, sizeof(inode_p->addr));
    // Reset all sectors of the array
    fs_reset_addr(inode_p);
    // It must be the first indir sector as we only have 8 in addr.
    inode_p->addr[0] = indir_sector;
    // If the offset is greater than the array size, then we should 
    // convert it to a large block first
    fs_set_file_large(inode_p);
  }

  return ret;
}

// These two are used to distinguish data and indir sector when allocating
// a new sector
#define FS_INDIR_SECTOR 1
#define FS_DATA_SECTOR  0

/*
 * fs_addr_read_or_alloc() - This function either reads and returns a given
 *                           sector pointer's value, or allocate a new block
 *                           for it. 
 *
 * The return value is either the value read or allocated. Return 
 * invalid sector if allocation fails
 *
 * If the indir flag is set to 1, then we also initialize it as an indirection
 * sector. Otherwise the sector is not initialized
 *
 * Note that the pointer must be in the buffer area because we will pin it
 *
 * Also, the sector_p buffer could be loaded using read-only mode. We will set
 * it as dirty if we truly write into it other than simply reading its value.
 */
sector_t fs_addr_read_or_alloc(Storage *disk_p, sector_t *sector_p, int type) {
  assert(type == FS_INDIR_SECTOR || type == FS_DATA_SECTOR);
  buffer_pin(disk_p, sector_p);
  sector_t sector = *sector_p;
  if(sector == FS_INVALID_SECTOR) {
    sector = fs_alloc_sector(disk_p);
    // This is valid even when the allocation fails, because we did not
    // change the value by doing this when it fails.
    *sector_p = sector;
    // If allocation succeeds we set the buffer as dirty
    if(sector != FS_INVALID_SECTOR) {
      buffer_set_dirty(disk_p, sector_p);
    }
    // If allocation succeeds and indir is 1 we also initialize it
    if(type == FS_INDIR_SECTOR && sector != FS_INVALID_SECTOR) {
      // Blind write
      sector_t *data_p = (sector_t *)write_lba(disk_p, sector);
      for(sector_t i = 0;i < context.id_per_indir_sector;i++) {
        data_p[i] = FS_INVALID_SECTOR;
      }
    }
  }

  buffer_unpin(disk_p, sector_p);
  return sector;
}

/*
 * fs_get_file_sector_for_write_large_file() - This function finds or creates a
 *                                             sector for write in a large file
 *
 * The inode should be pinned. The sector should be larger than ADDR size.
 * The inode must point to a large file
 *
 * This function returns invalid sector if allocation fails when trying to
 * add an indirection sector or a data sector. Otherwise it returns the new 
 * data sector we added for found.
 */
sector_t fs_get_file_sector_for_write_large_file(Storage *disk_p, 
                                                 Inode *inode_p, 
                                                 sector_t sector) {
  assert(buffer_is_pinned(disk_p, inode_p) == 1);
  assert(sector >= FS_ADDR_ARRAY_MAX);
  assert(fs_is_file_large(inode_p) == 1);
  sector_t ret;
  // These two are the index and offset of/within the first indirection level
  sector_t indir_index = sector / context.id_per_indir_sector;
  sector_t indir_offset = sector % context.id_per_indir_sector;
  // If the index is still in large file range but not extra large file range
  if(indir_index < (FS_ADDR_ARRAY_MAX - 1)) {
    // Read or alloc the first indir sector
    sector_t indir_sector = \
      fs_addr_read_or_alloc(disk_p,
                            &inode_p->addr[indir_index], 
                            FS_INDIR_SECTOR);

    // Only proceed to check the indir sector if we have not failed
    // in the previous stage
    if(indir_sector == FS_INVALID_SECTOR) {
      ret = FS_INVALID_SECTOR;
    } else {
      assert(inode_p->addr[indir_index] != FS_INVALID_SECTOR);
      // If the target sector is not in the extra large range
      // we just write the sector
      // Should pin it because we called alloc sector
      sector_t *data_p = \
        (sector_t *)read_lba(disk_p, indir_sector);
      buffer_pin(disk_p, data_p);

      // Then read or alloc a data sector for the first indir sector
      // If fails then ret will be invalid sector
      ret = fs_addr_read_or_alloc(disk_p,
                                  &data_p[indir_offset], 
                                  FS_DATA_SECTOR);

      // Unpin the indirection buffer here before return
      buffer_unpin(disk_p, data_p);
    }
  } else {
    // If we are in this branch, then we fall into the extra large range
    assert(sector >= context.extra_large_start_sector);
    sector -= context.extra_large_start_sector;
    indir_index = sector / context.id_per_indir_sector;
    // The index cannot overflow a indir sector
    assert(indir_index < context.id_per_indir_sector);
    indir_offset = sector % context.id_per_indir_sector;
    // Read or allocate it
    sector_t first_indir_sector = \
      fs_addr_read_or_alloc(disk_p,
                            &inode_p->addr[FS_ADDR_ARRAY_MAX - 1], 
                            FS_INDIR_SECTOR);
    if(first_indir_sector != FS_INVALID_SECTOR) {
      // If we have set the last sector in addr. array then the file is also
      // extra large
      assert(fs_is_file_extra_large(inode_p) == 1);
      sector_t *first_indir_p = \
        (sector_t *)read_lba(disk_p, first_indir_sector);
      // It will be unpinned at the very end
      buffer_pin(disk_p, first_indir_p);
      sector_t second_indir_sector = \
        fs_addr_read_or_alloc(disk_p,
                              &first_indir_p[indir_index], 
                              FS_INDIR_SECTOR);
      if(second_indir_sector != FS_INVALID_SECTOR) {
        sector_t *second_indir_p = \
          (sector_t *)read_lba(disk_p, second_indir_sector);
        buffer_pin(disk_p, second_indir_p);
        // If the allocation fails then ret will naturally be invalid sector
        ret = fs_addr_read_or_alloc(disk_p,
                                    &second_indir_p[indir_offset], 
                                    FS_DATA_SECTOR);
        buffer_unpin(disk_p, second_indir_p);
      } else {
        ret = FS_INVALID_SECTOR;
      }
      // Release the first indir sector
      buffer_unpin(disk_p, first_indir_p);
    } else {
      ret = FS_INVALID_SECTOR;
    }
  }

  return ret;
}

/*
 * fs_get_file_sector_for_write() - This function returns the sector ID
 *                                  to write into.
 *
 * If the sector does not exist, or the offset exceeds the current file
 * end, then we allocate sector for the indirection block, and then try again
 *
 * Note that this function may leave holes in the array of blocks or indirection
 * blocks. In these cases, the slot has value invalid sector ID. Any read 
 * operation to these ranges should return 0
 *
 * This function returns a sector ID for write. If it returns invalid ID then
 * we have run out of blocks.
 *
 * This function will pin the inode such that its buffer remains valid
 * after function return
 */
sector_t fs_get_file_sector_for_write(Storage *disk_p,
                                      Inode *inode_p,
                                      size_t offset) {
  // First pin the buffer, because we will read sectors
  buffer_pin(disk_p, inode_p);

  sector_t ret;
  sector_t sector = (sector_t)(offset / disk_p->sector_size);
  assert(((size_t)sector * disk_p->sector_size) == offset);
  if(fs_is_file_large(inode_p) == 0) {
    // If it is not large, then check the sector offset
    if(sector >= FS_ADDR_ARRAY_MAX) {
      // This does not logically change the file
      sector_t indir_sector = fs_convert_to_large(disk_p, inode_p);
      if(indir_sector == FS_INVALID_SECTOR) {
        ret = FS_INVALID_SECTOR;
      } else {
        ret = fs_get_file_sector_for_write_large_file(disk_p, inode_p, sector);
      }
    } else {
      // If it fails then ret will be invalid sector
      ret = fs_addr_read_or_alloc(disk_p, 
                                  &inode_p->addr[sector], 
                                  FS_DATA_SECTOR);
    }
  } else {
    // Just forward it to the function
    ret = fs_get_file_sector_for_write_large_file(disk_p, inode_p, sector);
  }
  
  buffer_unpin(disk_p, inode_p);
  return ret;
}

/*
 * fs_alloc_sector_for_dir() - This function allocates a sector for holding
 *                             directory entries
 *
 * We fill the sector with unused entries.
 *
 * If allocation fails we return invalid sector. The buffer should be pinned
 */
sector_t fs_alloc_sector_for_dir(Storage *disk_p, 
                                 Inode *inode_p, 
                                 sector_t alloc_for) {
  assert(buffer_is_pinned(disk_p, inode_p) == 1);
  // Allocate for the linear sector specifid in the argument
  sector_t sector = \
    fs_get_file_sector_for_write(disk_p, 
                                 inode_p, 
                                 (size_t)alloc_for * disk_p->sector_size);
  // If the sector is allocated then initialize its content
  if(sector != FS_INVALID_SECTOR) {
    DirEntry *entry_p = (DirEntry *)write_lba(disk_p, sector);
    for(int i = 0;i < context.dir_per_sector;i++) {
      entry_p[i].inode = FS_INVALID_INODE;
    }
  }

  return sector;
}

/*
 * fs_add_dir_entry() - This function adds a new dir entry for finds an unused 
 *                      entry in the given inode
 *
 * This function will pin the inode, and unpins it before return. In order for
 * the dir entry to remain valid, the caller should be responsible not to
 * invalidate it.
 *
 * This function sets the buffer as dirty. The caller could directly write into
 * it.
 *
 * If sector allocation fails, this function returns NULL. Otherwise returns the
 * pointer from the buffer.
 */
DirEntry *fs_add_dir_entry(Storage *disk_p, Inode *inode_p) {
  // Make sure we are operating on inode that represents dir
  assert(fs_get_file_type(inode_p) == FS_INODE_TYPE_DIR);

  buffer_pin(disk_p, inode_p);
  DirEntry *ret = NULL;
  // Find the sector. Note that size of the directory is always a
  // multiple of sectors
  size_t dir_size = fs_get_file_size(inode_p);
  // If the dir size is 0 then we allocate the first sector to it
  if(dir_size == 0) {
    // Allocate first sector
    sector_t new_sector = fs_alloc_sector_for_dir(disk_p, inode_p, 0);
    // EARLY RETURN
    if(new_sector == FS_INVALID_SECTOR) {
      buffer_unpin(disk_p, inode_p);
      return NULL;
    }

    fs_set_file_size(inode_p, disk_p->sector_size);
    dir_size = disk_p->sector_size;
  }
  assert(dir_size != 0);
  assert(dir_size % disk_p->sector_size == 0);
  sector_t last_sector = (sector_t)(dir_size / disk_p->sector_size) - 1;
  assert(last_sector != (sector_t)-1);

  // Tentatively read it. If we do need to modify the sector we just
  // set dirty later
  // We scan all sectors from the last sector
  for(sector_t sector = last_sector;sector != (sector_t)-1;sector--) {
    DirEntry *entry_p = (DirEntry *)read_lba(disk_p, sector);
    // Check every dir entry
    for(int i = 0;i < context.dir_per_sector;i++) {
      if(entry_p[i].inode == FS_INVALID_INODE) {
        // This is the entry we are looking for
        ret = entry_p + i;
        // Set buffer as dirty because we intend to write it back
        buffer_set_dirty(disk_p, ret);
      }
    }
  }

  // If still could not find entry, then allocate one
  if(ret == NULL) {
    // Allocate the next sector
    sector_t new_sector = \
      fs_alloc_sector_for_dir(disk_p, inode_p, last_sector + 1);
    // EARLY RETURN
    if(new_sector == FS_INVALID_SECTOR) {
      buffer_unpin(disk_p, inode_p);
      return NULL;
    }

    // Update the sector size
    dir_size += disk_p->sector_size;
    fs_set_file_size(inode_p, dir_size);
    // This is the first entry, and it must be not used
    // Also this buffer is set to dirty when we load it
    DirEntry *entry_p = (DirEntry *)read_lba_for_write(disk_p, new_sector);
    ret = entry_p;
  }
 
  buffer_unpin(disk_p, inode_p);
  return ret;
}

/*
 * fs_is_valid_char() - Returns 1 if the char is valid for file name
 *
 * Valid chars are:
 *   1. Alphabet
 *   2. Numeric digits
 *   3. Underline, dash and dot
 *   4. Space character
 */
int fs_is_valid_char(char ch) {
  if(ch >= 'A' && ch <= 'Z') {
    return 1;
  } else if(ch >= 'a' && ch <= 'z') {
    return 1;
  } else if(ch >= '0' && ch <= '9') {
    return 1;
  } else if(ch == '.' || ch == '-' || ch == '_' || ch == ' ') {
    return 1;
  }

  return 0;
}

#define FS_SET_DIR_NAME_DISALLOW_DOT 0
#define FS_SET_DIR_NAME_ALLOW_DOT    1

/*
 * fs_set_dir_name() - This function sets the directory name
 *
 * This function proceeds as follows:
 *   1. If the length of the name exceeds the maximum length then return 
 *      FS_ERR_NAME_TOO_LONG
 *      1.1 Defined by FS_DIR_ENTRY_NAME_MAX, not including any '\0' padding
 *      1.2 We do not use '\0' to terminate the file name either
 *   2. If there is any forbidden char, then we return FS_ERR_ILLEGAL_CHAR
 *      2.1 alphanumeric, underline, dash, and space are allowed
 *      2.2 All other characters are not allowed
 *   3. If the name itself is illegal, then we return FS_ERR_ILLEGAL_NAME
 *      3.1 Names that only has '.' character
 *      3.2 Names that only has space character
 *
 * If we need to allow names that only have dot, then the allow_all_dot should 
 * be set to 1. This feature is only used for initializing a directory
 *
 * This function will set the entry as dirty.
 */
int fs_set_dir_name(Storage *disk_p, 
                    DirEntry *entry_p, 
                    const char *name, 
                    int allow_all_dot) {
  int len = strlen(name);
  if(len > FS_DIR_ENTRY_NAME_MAX) {
    return FS_ERR_NAME_TOO_LONG;
  }

  const char *p = name;
  // As long as any of the character is invalid, the entire name is invalid
  while(*p != '\0') {
    if(fs_is_valid_char(*p) == 0) {
      return FS_ERR_ILLEGAL_CHAR;
    }
    p++;
  }

  p = name;
  // Are set to 0 if we see anything other than a dot/space
  int all_dots = 1;
  int all_space = 1;
  while(*p != '\0') {
    if(*p != '.') {
      all_dots = 0; 
    }

    if(*p != ' ') {
      all_space = 0;
    }

    p++;
  }

  // Manually disable it if we allow names such as . and ..
  if(allow_all_dot == FS_SET_DIR_NAME_ALLOW_DOT) {
    all_dots = 0;
  }

  // If any of these two are assigned 1
  if(all_dots == 1 || all_space == 1) {
    return FS_ERR_ILLEGAL_NAME;
  }

  // Make the change available if we need to change the name
  buffer_set_dirty(disk_p, entry_p);
  // Set padding first (it's actually faster)
  memset(entry_p->name + len, 0x00, FS_DIR_ENTRY_NAME_MAX);
  // We do not use strcpy because we do not copy the trailing 0
  memcpy(entry_p->name, name, len);

  return FS_SUCCESS;
}

/*
 * fs_print_dir_name() - This function prints the name of a given directory
 *
 * We print the name without any modification. Just the name will be printed.
 * This function takes a pointer for printing to an FP. The fp could be
 * either stderr or stdout
 */
void fs_print_dir_name(DirEntry *entry_p, FILE *fp) {
  const char *p = entry_p->name;
  while(*p != '\0') {
    fputc(*p, fp);
    p++;
  }

  return;
}

/*
 * fs_init_root() - This function initializes the root directory
 *
 * This function must be called after the context is loaded
 */
void fs_init_root(Storage *disk_p) {
  // Allocate a sector for inode 0 to hold its initial default dir
  sector_t sector = fs_alloc_sector(disk_p);
  if(sector == FS_INVALID_SECTOR) {
    fatal_error("Failed to allocate sector for root directory");
  }

  Inode *inode_p = fs_load_inode_sector(disk_p, FS_ROOT_INODE, 1);
  inode_p->flags |= FS_INODE_IN_USE;
  // Size of a directory is the number of sectors it occupies
  fs_set_file_type(inode_p, FS_INODE_TYPE_DIR);

  DirEntry *entry_p_dot = fs_add_dir_entry(disk_p, inode_p);
  DirEntry *entry_p_dot_dot = fs_add_dir_entry(disk_p, inode_p);
  if(entry_p_dot == NULL || entry_p_dot_dot == NULL) {
    fatal_error("Failed to allocate initial entries for root");
  }

  int dir_name_ret;
  // Set the name of these two entries
  dir_name_ret = \
    fs_set_dir_name(disk_p, entry_p_dot, ".", FS_SET_DIR_NAME_ALLOW_DOT);
  assert(dir_name_ret == FS_SUCCESS);
  dir_name_ret = \
    fs_set_dir_name(disk_p, entry_p_dot_dot, ".", FS_SET_DIR_NAME_ALLOW_DOT);
  assert(dir_name_ret == FS_SUCCESS);

  // Set the inode. Both point to the current directory
  entry_p_dot->inode = entry_p_dot_dot->inode = FS_ROOT_INODE;

  info("Finished initializing root directory");

  return;
}

/*
 * fs_init() - This function initializes an empty FS on a raw storage
 *
 * The init_root flag is used for debugging purposes. It indicates whether
 * we initialize the root directory also. For debugging we do not wish
 * so, because it will disrupt sector and inode allocator
 */
void _fs_init(Storage *disk_p, size_t total_sector, size_t start_sector, 
             int init_root) {
  assert(start_sector < total_sector - 1);
  assert(total_sector <= disk_p->sector_count);
  size_t inode_start_sector = start_sector + 1;
  // This is the number of total usable blocks for inode and file
  size_t usable_sector_count = total_sector - start_sector - 1;
  size_t inode_sector_count = \
    fs_init_inode(disk_p, inode_start_sector, total_sector);
  size_t free_sector_count = usable_sector_count - inode_sector_count;
  info("  # of inode sectors: %lu; free sectors: %lu",
       inode_sector_count,
       free_sector_count);
  // This is the absolute sector ID of the free start sector
  size_t free_start_sector = inode_start_sector + inode_sector_count;
  size_t free_list_size = \
    fs_init_free_list(disk_p, free_start_sector, total_sector);
  info("  Free list size: %lu; First free sector: %lu", 
       free_list_size,
       free_start_sector);

  // At last, we init the super block
  SuperBlock *sb_p = (SuperBlock *)write_lba(disk_p, start_sector);
  // We use the signature to verify the fs type
  memcpy(sb_p->signature, FS_SIG, FS_SIG_SIZE);
  sb_p->isize = (sector_t)inode_sector_count;
  sb_p->fsize = (sector_t)free_sector_count;
  // There is no cached free block and free inodes. The first write operation
  // into the file system will find one
  sb_p->free_array.nfree = 0;
  memset(sb_p->free_array.free, 0x0, sizeof(sb_p->free_array.free));
  // The first element is the sector ID for the sector that stores 
  // the free list
  sb_p->free_array.free[0] = (sector_t)free_start_sector;
  sb_p->ninode = 0;
  memset(sb_p->inode, 0x0, sizeof(sb_p->inode));
  sb_p->flock = sb_p->ilock = 0;
  sb_p->fmod = 0;
  sb_p->time[0] = sb_p->time[1] = 0;

  // Make sure the super block goes to disk
  buffer_flush_all_no_rm(disk_p);
  info("Finished writing the super block");

  fs_load_context(disk_p);
  if(init_root == 1) {
    // Set up the root node (also allocate inode 0)
    fs_init_root(disk_p);
  }

  return;
}

// This is called by non-debugging routines
void fs_init(Storage *disk_p, size_t total_sector, size_t start_sector) {
  _fs_init(disk_p, total_sector, start_sector, 1);
}

/*
 * fs_alloc_sector() - This function allocates a new sector using either the SB
 *                     or the linked list
 *
 * Returns 0 if allocation failed (0 is not a valid block ID)
 */
sector_t fs_alloc_sector(Storage *disk_p) {
  // First read the super block, setting dirty flag
  SuperBlock *sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
  buffer_pin(disk_p, sb_p);

  sector_t ret = 0;
  // If there are cached free values, then just get one
  if(sb_p->free_array.nfree != 0) {
    ret = sb_p->free_array.free[sb_p->free_array.nfree];
    sb_p->free_array.nfree--;
  } else {
    sector_t free_list_head = sb_p->free_array.free[0];
    // If there is no next block, then we have exhausted free blocks
    if(free_list_head == FS_INVALID_SECTOR) {
      ret = FS_INVALID_SECTOR;
    } else {
      // We use this sector as the free sector, and copy its free list into
      // the super block
      ret = free_list_head;
      // Read the free list head, and copy the free array into the temp
      // object (because the sb may have been evicted)
      sector_t *data_p = (sector_t *)read_lba(disk_p, free_list_head);
      memcpy(&sb_p->free_array, data_p, sizeof(FreeArray));
    }
  }

  // Make sure no buffer is pinned at the end
  buffer_unpin(disk_p, sb_p);
  return ret;
}

/*
 * fs_free_sector() - This function frees a sector.
 *
 * We first tries to add the freed sector into the super block's cache.
 * If the cache is full, we then move the array into the freed block, and 
 * then empty the super block's cache, and link the current block into
 * the free chain
 */
void fs_free_sector(Storage *disk_p, sector_t sector) {
  SuperBlock *sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
  buffer_pin(disk_p, sb_p);

  assert(sb_p->free_array.nfree <= (FS_FREE_ARRAY_MAX - 1));
  // If the free list is not full, we just put it into the sb and 
  // increment nfree
  if(sb_p->free_array.nfree < (FS_FREE_ARRAY_MAX - 1)) {
    sb_p->free_array.nfree++;
    sb_p->free_array.free[sb_p->free_array.nfree] = sector;
  } else {
    // Otherwise, we first copy the current free array object into the new block
    FreeArray free_array;
    memcpy(&free_array, &sb_p->free_array, sizeof(FreeArray));
    // Then link the newly freed block into the super block
    sb_p->free_array.nfree = 0;
    sb_p->free_array.free[0] = sector;
    // Create a buffer entry for the sector
    void *data_p = write_lba(disk_p, sector);
    memcpy(data_p, &free_array, sizeof(FreeArray));
  }

  buffer_unpin(disk_p, sb_p);
  return;
}

/*
 * fs_load_inode_sector() - This function loads the sector an inode is in
 *                          and returns the pointer to that inode
 *
 * Note that this function does not check whether the inode number is
 * valid or not (it may be out of range if programming error happens)
 *
 * If write_flag is 1, then we load the sector for write. Otherwise load it
 * for read.
 *
 * Note that we do not pin the inode. The caller should be responsible for this
 */
Inode *fs_load_inode_sector(Storage *disk_p, inode_id_t inode, int write_flag) {
  sector_t sector_num = inode / context.inode_per_sector;
  size_t offset = inode % context.inode_per_sector;
  sector_num += (FS_SB_SECTOR + 1);

  Inode *inode_p = NULL;
  if(write_flag == 1) {
    inode_p = (Inode *)read_lba_for_write(disk_p, sector_num);
  } else {
    inode_p = (Inode *)read_lba(disk_p, sector_num);
  }

  return inode_p + offset;
}

/*
 * fill_inode_free_array() - This function fills the inode free array
 *
 * We start from the first sector after the sb, and scans until we reach
 * the last inode sector.
 *
 * Note that the passed super block must be a valid one, i.e. no other
 * buffer operation may happen between the load of the sb and the usage of
 * this sector.
 *
 * This function returns a pointer to the new SB block, which is read
 * for write. The caller could use this pointer to allocate inodes.
 *
 * sb should be pinned in the buffer
 */
SuperBlock *fill_inode_free_array(Storage *disk_p, SuperBlock *sb_p) {
  // Only call this function when the inode array is empty
  assert(sb_p->ninode == 0);
  assert(buffer_is_pinned(disk_p, sb_p));

  // inode sector is just after the super block
  sector_t current_sector = FS_SB_SECTOR + 1;
  // Number of inodes we have scanned
  int count = 0;
  inode_id_t current_inode = 0;
  // It can hold 100 inodes
  inode_id_t free_inode_list[FS_FREE_ARRAY_MAX];
  for(sector_t i = 0;i < context.inode_sector_count;i++) {
    Inode *inode_p = (Inode *)read_lba(disk_p, current_sector);
    for(size_t j = 0;j < context.inode_per_sector;j++) {
      // If the inode is not in-use
      if((inode_p[j].flags & FS_INODE_IN_USE) == 0) {
        // The inode could not be the root inode, otherwise the fs is broken
        //assert(current_inode != FS_ROOT_INODE);
        // Also the inode could not be the invalid value, otherwise sector_t
        // would overflow
        //assert(current_inode != FS_INVALID_INODE);

        // Otherwise just add the inode into the list of inodes
        free_inode_list[count] = current_inode;
        count++;
        if(count == FS_FREE_ARRAY_MAX) {
          break;
        }
      }
      // Then go to check the next inode
      current_inode++;
    }

    if(count == FS_FREE_ARRAY_MAX) {
      break;
    }
    current_sector++;
  }

  // Then update the super block
  sb_p->ninode = count;
  // Just copy the inodes we have in the list
  memcpy(sb_p->inode, free_inode_list, sizeof(free_inode_list[0]) * count);

  return sb_p;
}

/*
 * fs_alloc_inode() - This function allocates an unused inode
 *
 * We first search the super block, and if the super block does not have
 * any cached inode, we need to scan the entire inode map and find one
 *
 * This function returns the inode number. (-1) means allocation failure
 */
inode_id_t fs_alloc_inode(Storage *disk_p) {
  SuperBlock *sb_p = (SuperBlock *)read_lba(disk_p, FS_SB_SECTOR);
  buffer_pin(disk_p, sb_p);

  inode_id_t ret;
  // If the array is empty, we just fill it first
  if(sb_p->ninode == 0) {
    sb_p = fill_inode_free_array(disk_p, sb_p);
  }

  // If the inode list is still empty, then we could not find 
  // any more inodes, and return failure
  if(sb_p->ninode == 0) {
    ret = FS_INVALID_INODE;
  } else {
    // Note that here we decrement first and then get inode number
    sb_p->ninode--;
    ret = sb_p->inode[sb_p->ninode];
    // Load the sector that holds the inode, and make it dirty because we 
    // are writing into this inode
    Inode *inode_p = fs_load_inode_sector(disk_p, ret, 1);
    assert((inode_p->flags & FS_INODE_IN_USE) == 0);
    // Clear its previous content
    memset(inode_p, 0x0, sizeof(Inode));
    // Mark it as in-use
    inode_p->flags |= FS_INODE_IN_USE;
  }
  
  buffer_unpin(disk_p, sb_p);
  return ret;
}

/*
 * fs_free_inode() - This function frees an inode
 *
 * If the inode free array in the sb is not yet full, we just add it
 * Otherwise we discard the inode number. Because the allocation information
 * is stored in the inode itself, we do not need to precisely track the 
 * inode usage in the sb
 */
void fs_free_inode(Storage *disk_p, inode_id_t inode) {
  SuperBlock *sb_p = (SuperBlock *)read_lba(disk_p, FS_SB_SECTOR);
  buffer_pin(disk_p, sb_p);

  // If it is not full, we just use it. Otherwise we ignore the free
  // inode list in sb and directly mask off the flag
  if(sb_p->ninode != FS_FREE_ARRAY_MAX) {
    // Upgrade to write
    sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
    sb_p->inode[sb_p->ninode] = inode;
    sb_p->ninode++;
  }

  // Load the sector containing this inode, and set it as dirty
  Inode *inode_p = fs_load_inode_sector(disk_p, inode, 1);
  // Make sure it is an allocated inode
  assert(inode_p->flags & FS_INODE_IN_USE);
  // Mask off the inodes
  inode_p->flags &= (~FS_INODE_IN_USE);

  buffer_unpin(disk_p, sb_p);
  return;
}

/////////////////////////////////////////////////////////////////////
// Test Cases
/////////////////////////////////////////////////////////////////////

#define DEBUG
#ifdef DEBUG

void test_lba_rw(Storage *disk_p) {
  info("=\n=Testing LBA r/w...\n=");
  uint8_t buffer[DEFAULT_SECTOR_SIZE];
  int prev_percent = 0;
  for(size_t i = 0;i < disk_p->sector_count;i++) {
    memset(buffer, (char)i, DEFAULT_SECTOR_SIZE);
    disk_p->write(disk_p, i, buffer);
    // Current progress
    int current_percent = (int)(((double)i / disk_p->sector_count) * 100);
    if(current_percent != prev_percent) {
      fprintf(stderr, "\r  Write progress %d%%", current_percent);
      prev_percent = current_percent;
    }
  }
  putchar('\n');

  prev_percent = 0;
  for(size_t i = 0;i < disk_p->sector_count;i++) {
    disk_p->read(disk_p, i, buffer);
    for(int j = 0;j < DEFAULT_SECTOR_SIZE;j++) {
      if(buffer[j] != (uint8_t)i) {
        fatal_error("LBA read fail (i = %lu, j = %d)", i, j);
      }
    }

    int current_percent = (int)(((double)i / disk_p->sector_count) * 100);
    if(current_percent != prev_percent) {
      fprintf(stderr, "\r  Read progress %d%%", current_percent);
      prev_percent = current_percent;
    }
  }
  putchar('\n');

  return;
}

void test_buffer(Storage *disk_p) {
  info("=\n=Testing buffer...\n=");
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

void test_pin_buffer(Storage *disk_p) {
  info("=\n=Testing buffer pin/unpin...\n=");
  // First remove all buffers to make it into a known state
  buffer_flush_all(disk_p);

  // First make sure there is no pinned buffer
  assert(buffer_count_pinned() == 0UL);

  const int pinned_count = 5;
  // Then read 5 buffers
  for(int i = 0;i < pinned_count;i++) {
    uint8_t *p = (uint8_t *)read_lba(disk_p, (uint64_t)i);
    // Pin the buffer using some pointer to the middle of the buffer
    buffer_pin(disk_p, p + i * 20);
  }

  // Print to see whether we have the pinned flag set
  buffer_print();
  assert(buffer_count_pinned() == (size_t)pinned_count);

  // Read another 50 buffers and see whether the previous 5 are evicted
  for(int i = 100;i < 150;i++) {
    read_lba(disk_p, (uint64_t)i);
  }

  // Print to see whether pinned buffer is still in the buffer list
  buffer_print();
  assert(buffer_count_pinned() == (size_t)pinned_count);

  // Finally, unpin these buffers and then test the pinned count
  for(int i = pinned_count - 1;i >= 0;i--) {
    uint8_t *p = (uint8_t *)read_lba(disk_p, (uint64_t)i);
    // Pin the buffer using some pointer to the middle of the buffer
    buffer_unpin(disk_p, p + 511);
  }

  buffer_print();
  assert(buffer_count_pinned() == 0UL);

  return;
}

void test_fs_init(Storage *disk_p) {
  info("=\n=Testing fs initialization...\n=");

  info("Inode size: %lu", sizeof(Inode));
  info("SuperBlock size: %lu", sizeof(SuperBlock));
  info("Entry size: %lu", sizeof(DirEntry));

  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);

  // Note that we must put the super block on the given location
  // Call the special version
  _fs_init(disk_p, disk_p->sector_count, FS_SB_SECTOR, 0);
  // Fill the parameters
  fs_load_context(disk_p);

  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);

  return;
}

void test_alloc_sector(Storage *disk_p) {
  info("=\n=Testing sector allocation...\n=");

  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);

  const char *round_desp[] = {
    "Low to high",
    "High to low",
    "Random",
    "Verify"
  };

  const size_t free_sector_start = context.free_start_sector;
  const size_t total_sector_count = context.total_sector_count;
  const size_t free_sector_count = context.free_sector_count;
  // Make sure the result is correct
  assert(total_sector_count == disk_p->sector_count);

  // Allocate a bitmap to record which sector is good and which is not
  uint8_t *sector_map = \
    malloc(sizeof(uint8_t) * free_sector_count);
  assert(sector_map != NULL);
  int round = 0;
  int prev_percent = 0;
  while(1) {
    memset(sector_map, 
          0x00, 
          sizeof(uint8_t) * free_sector_count);

    sector_t sector;
    size_t count = 0;
    do { 
      sector = fs_alloc_sector(disk_p);
      if(sector != FS_INVALID_SECTOR) {
        count++;
        // Must be within free sector
        assert(sector >= free_sector_start);
        assert(sector < total_sector_count);
        size_t index = sector - free_sector_start;
        assert(sector_map[index] == 0);
        sector_map[index] = 1;

        int current_percent = \
          (int)(((double)count / context.free_sector_count) * 100);
        if(current_percent != prev_percent) {
          prev_percent = current_percent;
          fprintf(stderr, "\r  Allocated %d%% of all free blocks", 
                  prev_percent);
        }
      }
    } while(sector != FS_INVALID_SECTOR);
    putchar('\n');
    
    info("Round %d (%s): Allocated %lu sectors. Now verifying...", 
         round, 
         round_desp[round],
         count);

    // Check whether all sectors are allocated
    for(size_t i = free_sector_start;i < total_sector_count;i++) {
      assert(sector_map[i - free_sector_start] == 1);
    }

    info("  ...Pass");
    info("  Free allocated sectors...");
    if(round == 0) {
      for(sector_t i = free_sector_start;i < total_sector_count;i++) {
        fs_free_sector(disk_p, i);
      }
    } else if(round == 1) {
      for(sector_t i = total_sector_count - 1;i >= free_sector_start;i--) {
        fs_free_sector(disk_p, i);
      }
    } else if(round == 2) {
      srand(time(NULL));
      for(int i = 0;i < free_sector_count;i++) {
        // [free_sector_start, total_sector_count)
        sector_t start = \
          ((sector_t)rand() % free_sector_count) + free_sector_start;
        // Use the map as a hash table to find sectors that are not yet
        // freed
        while(sector_map[start - free_sector_start] == 0) {
          start++;
          if(start == total_sector_count) {
            start = free_sector_start;
          }
        }

        // Clear it and then free
        sector_map[start - free_sector_start] = 0;
        fs_free_sector(disk_p, start);
      }
    } else {
      info("Cleaning up");
      for(sector_t i = free_sector_start;i < total_sector_count;i++) {
        fs_free_sector(disk_p, i);
      }

      break;
    }

    info("  ...Done");

    round++;
  } // while(1)

  free(sector_map);
  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);

  return;
}

void test_alloc_inode(Storage *disk_p) {
  info("=\n=Testing allocating inode...\n=");

  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);

  const char *round_desp[] = {
    "Low to high",
    "High to low",
    "Random",
    "Verify"
  };

  // Number of rounds
  int round_count = sizeof(round_desp) / sizeof(round_desp[0]);
  
  // Preparing the array for recording which inode is allocated
  const size_t alloc_size = sizeof(uint8_t) * context.total_inode_count;
  uint8_t *flag_p = (uint8_t *)malloc(alloc_size);
  int round = 0;

  while(1) {
    memset(flag_p, 0x00, alloc_size);
    inode_id_t inode;
    int count = 0;
    int prev_percent = 0;
    do {
      // Starts from 0 and ends at max inode
      inode = fs_alloc_inode(disk_p);
      // If allocation is a success we set it to 1
      if(inode != FS_INVALID_INODE) {
        assert(inode < context.total_inode_count);
        assert(flag_p[inode] == 0);
        flag_p[inode] = 1;
        count++;

        // Also check that the inode is indeed allocated (do not write)
        Inode *inode_p = fs_load_inode_sector(disk_p, inode, 0);
        assert(inode_p->flags & FS_INODE_IN_USE);

        int current_percent = \
          (int)(((double)count / context.total_inode_count) * 100);
        if(current_percent != prev_percent) {
          prev_percent = current_percent;
          fprintf(stderr, "\r  Allocated %d%% inodes", current_percent);
        }
      }
    } while(inode != FS_INVALID_INODE);
    putchar('\n');

    info("Round %d (%s): Allocated %lu inodes. Now verifying...", 
         round, 
         round_desp[round],
         count);

    for(int i = 0;i < context.total_inode_count;i++) {
      if(flag_p[i] == 0) {
        fatal_error("Inode %d is not allocated", i);
      }
    }

    info("  ...Pass");
    if(round < round_count - 1) {
      info("  Free allocated sectors...");
    }

    if(round == 0) {
      for(int i = 0;i < context.total_inode_count;i++) {
        fs_free_inode(disk_p, i);
      }
    } else if(round == 1) {
      for(int i = context.total_inode_count - 1;i >= 0;i--) {
        fs_free_inode(disk_p, i);
      }
    } else if(round == 2) {
      srand(time(NULL));
      for(int i = 0;i < context.total_inode_count;i++) {
        inode_id_t start = (inode_id_t)rand() % context.total_inode_count;
        // Use the map as a hash table to find sectors that are not yet
        // freed
        while(flag_p[start] == 0) {
          start++;
          if(start == context.total_inode_count) {
            start = 0;
          }
        }

        // Clear it and then free
        flag_p[start] = 0;
        fs_free_inode(disk_p, start);
      }
    } else {
      info("Cleaning up");
      for(int i = 0;i < context.total_inode_count;i++) {
        fs_free_inode(disk_p, i);
      }
      break;
    }

    info("  ...Done");
    round++;
  }

  free(flag_p);
  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);
  return;
}

void test_get_sector(Storage *disk_p) {
  info("=\n=Testing getting sector for read/write...\n=");
  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);

  // Allocate an inode object and then try filling its sectors
  inode_id_t inode = fs_alloc_inode(disk_p);
  assert(inode != FS_INVALID_INODE);
  Inode *inode_p = fs_load_inode_sector(disk_p, inode, 1);
  //buffer_pin(disk_p, inode_p);
  assert(fs_is_file_large(inode_p) == 0 && 
         fs_is_file_extra_large(inode_p) == 0);
  // This is the maximum number of sectors we could support in one file
  const size_t sector_count_for_test = \
    context.id_per_indir_sector * \
      (FS_ADDR_ARRAY_MAX - 1 + context.id_per_indir_sector);
  info("# of sector ID per indirection sector: %u", 
       (uint32_t)context.id_per_indir_sector); 
  info("Allocating %u sectors for a single file...", 
       (uint32_t)sector_count_for_test);
  // Index is the sector in the file and content is the sector ID on the disk
  sector_t *file_sector_map = malloc(sizeof(sector_t) * sector_count_for_test);
  // Index is the sector on the disk - free start sector, and content is 1
  // or 0
  uint8_t *disk_sector_map = \
    malloc(sizeof(uint8_t) * context.free_sector_count);
  memset(disk_sector_map, 0x00, sizeof(uint8_t) * context.free_sector_count);

  int count = 0;
  for(size_t i = 0;i < sector_count_for_test;i++) {
    // Note that this function requires byte offset
    sector_t sector = \
      fs_get_file_sector_for_write(disk_p, inode_p, i * disk_p->sector_size);
    
    // Run out of blocks
    if(sector == FS_INVALID_SECTOR) {
      break;
    } else {
      count++;
    }
    //assert(sector != FS_INVALID_SECTOR);
    assert(sector >= context.free_start_sector);
    assert(sector < context.free_end_sector);
    file_sector_map[i] = sector;
    // The sector must not be allocated
    assert(disk_sector_map[sector - context.free_start_sector] == 0);
    disk_sector_map[sector - context.free_start_sector] = 1;
  }
  
  info("  Allocated %d sectors to the inode", count);
  info("  (total free sector: %u)", context.free_sector_count);
  assert(fs_is_file_large(inode_p) == 1);
  assert(fs_is_file_extra_large(inode_p) == 1);

  info("Checking whether indirection sectors are allocated...");
  // We first evict all buffers to expose problems if any
  // and then re-read the inode
  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);
  inode_p = fs_load_inode_sector(disk_p, inode, 0);

  buffer_pin(disk_p, inode_p);
  // Iterate to find indirection sectors and also set it
  for(int i = 0;i < FS_ADDR_ARRAY_MAX;i++) {
    sector_t sector = inode_p->addr[i];
    // All must be set
    assert(sector != FS_INVALID_SECTOR);
    sector -= context.free_start_sector;
    assert(disk_sector_map[sector] == 0);
    disk_sector_map[sector] = 1;
  }

  // Set the last double-indirection sector
  sector_t *data_p = \
    (sector_t *)read_lba(disk_p, inode_p->addr[FS_ADDR_ARRAY_MAX - 1]);
  for(sector_count_t i = 0;i < context.id_per_indir_sector;i++) {
    // The last sector is not full
    if(data_p[i] == FS_INVALID_SECTOR) {
      break;
    }
    sector_t sector = data_p[i] - context.free_start_sector;
    assert(disk_sector_map[sector] == 0);
    disk_sector_map[sector] = 1;
  }
  buffer_unpin(disk_p, inode_p);
  info("  ...Pass");

  info("Checking whether all sectors are used...");
  // Validate the disk map to make sure that the entire disk is full
  for(sector_count_t i = 0;i < context.free_sector_count;i++) {
    assert(disk_sector_map[i] == 1);
  }
  info("  ...Pass");

  info("Reading the sector to verify...");
  int read_count = 0;
  // We can only read that many sectors
  for(size_t i = 0;i < sector_count_for_test;i++) {
    // If we exceed the maximum size
    if(i >= (size_t)((sector_t)-1)) {
      break;
    } else {
      read_count++;
    }

    sector_t sector = \
      fs_get_file_sector(disk_p, inode_p, i * disk_p->sector_size);
    if(i < count) {
      assert(sector == file_sector_map[i]);
    } else {
      assert(sector == FS_INVALID_SECTOR);
    }
  }
  info("  Verified %d sectors for read", read_count);
  info("  ...Pass");
  
  //buffer_unpin(disk_p, inode_p);
  buffer_flush_all(disk_p);
  assert(buffer_count_pinned() == 0UL);
  free(file_sector_map);
  free(disk_sector_map);
  return;
}

void test_init_root(Storage *disk_p) {
  info("=\n=Testing init the root directory...\n=");
  // This is the complete version of fs_init
  fs_init(disk_p, disk_p->sector_count, FS_SB_SECTOR);

  return;
}

void test_set_dir_name(Storage *disk_p) {
  info("=\n=Testing init the root directory...\n=");
  
  return;
}

// This is a list of function call backs that we use to test
void (*tests[])(Storage *) = {
  test_lba_rw,
  test_buffer,
  test_pin_buffer,
  test_fs_init,
  test_alloc_sector,
  test_alloc_inode,
#if WORD_SIZE != 4
  test_get_sector,
#endif
  test_init_root,
  test_set_dir_name,
  // This is the last stage
  free_mem_storage,
};

int main() {
  buffer_init();
  Storage *disk_p = get_mem_storage(2880);
  for(int i = 0;i < sizeof(tests) / sizeof(tests[0]);i++) {
    tests[i](disk_p);
  }

  info("Finished running all test cases (word size: %lu)", WORD_SIZE);

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

