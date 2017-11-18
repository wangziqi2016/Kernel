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

//#define BUFFER_FLUSH_DEBUG

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
 * buffer_flush_all() - This function flushes all buffers and writes back
 *                      those that are still dirty
 */
void buffer_flush_all(Storage *disk_p) {
  while(buffer_head_p != NULL) {
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

// This is the length of the free array
#define FS_FREE_ARRAY_MAX 100
#define FS_SIG_SIZE 4
#define FS_SIG "WZQ"
// This is the sector ID of the super block
#define FS_SB_SECTOR 1
// This indicates invalid sector numbers
#define FS_INVALID_SECTOR 0
// Since inode #0 is a valid one, we define invalid inode to be -1
#define FS_INVALID_INODE  ((uint16_t)-1)

typedef struct {
  // Number of elements in the local array
  uint16_t nfree;
  // The first word of this structure is the block number
  // to the next block that holds this list
  // All elements after the first one is the free blocks
  uint16_t free[FS_FREE_ARRAY_MAX];
} __attribute__((packed)) FreeArray;

// This defines the first block of the file system
typedef struct {
  // We use this to identify a valid super block
  char signature[FS_SIG_SIZE];
  // Number of sectors for i-node
  uint16_t isize;
  // Number of sectors for file storage
  // NOTE: We modified the semantics of this field.
  // In the original OFS design this is the absolute number of blocks
  // used by the FS and the bootsect. We make it relative to the inode
  // blocks
  uint16_t fsize;
  // Linked list of free blocks and the free array
  FreeArray free_array;
  // Number of free inodes as a fast cache in the following
  // array
  uint16_t ninode;
  uint16_t inode[FS_FREE_ARRAY_MAX];
  char flock;
  char ilock;
  char fmod;
  uint16_t time[2];
} __attribute__((packed)) SuperBlock;

#define FS_ADDR_ARRAY_SIZE 8

// This defines the inode structure
typedef struct {
  uint16_t flags;
  // Number of hardlinks to the file
  uint8_t nlinks;
  // User ID and group ID
  uint8_t uid;
  uint8_t gid;
  // High byte of 24 bit size field
  uint8_t size0;
  // Low word of 24 bit size field
  uint16_t size1;
  uint16_t addr[FS_ADDR_ARRAY_SIZE];
  // Access time
  uint16_t actime[2];
  // Modification time
  uint16_t modtime[2];
} __attribute__((packed)) Inode;

// This is the in-memory representation of the file system metadata
// We load the super block and initialize this object
// Once initialized it is never changed for the same fs
typedef struct {
  uint16_t sb_sector;
  uint16_t inode_start_sector;
  uint16_t inode_end_sector;
  uint16_t inode_sector_count;
  uint16_t free_start_sector;
  uint16_t free_end_sector;
  uint16_t free_sector_count;
  uint16_t total_sector_count;
  uint16_t total_inode_count;
  size_t inode_per_sector;
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

/*
 * load_context() - This function loads the context object using the super block
 *
 * For each file system mounted, this can only be done once, and then used
 * for the entire session
 *
 * This function should only be called after the fs has been initialized or 
 * mounted.
 */
void load_context(Storage *disk_p) {
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
    uint16_t *data = (uint16_t *)write_lba(disk_p, current_free);
    // There must be at least one free sector
    assert(free_end > (current_free + 1));
    // current_free should not be counted as a free block
    size_t delta = free_end - (current_free + 1);
    // These two are default values
    uint16_t next_free_list = current_free + 1;
    uint16_t free_sector_count = FS_FREE_ARRAY_MAX - 1;
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
 * fs_init() - This function initializes an empty FS on a raw storage
 */
void fs_init(Storage *disk_p, size_t total_sector, size_t start_sector) {
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
  sb_p->isize = (uint16_t)inode_sector_count;
  sb_p->fsize = (uint16_t)free_sector_count;
  // There is no cached free block and free inodes. The first write operation
  // into the file system will find one
  sb_p->free_array.nfree = 0;
  memset(sb_p->free_array.free, 0x0, sizeof(sb_p->free_array.free));
  // The first element is the sector ID for the sector that stores 
  // the free list
  sb_p->free_array.free[0] = (uint16_t)free_start_sector;
  sb_p->ninode = 0;
  memset(sb_p->inode, 0x0, sizeof(sb_p->inode));
  sb_p->flock = sb_p->ilock = 0;
  sb_p->fmod = 0;
  sb_p->time[0] = sb_p->time[1] = 0;

  // Make sure the super block goes to disk
  buffer_flush_all_no_rm(disk_p);
  info("Finished writing the super block");

  return;
}

/*
 * fs_alloc_sector() - This function allocates a new sector using either the SB
 *                     or the linked list
 *
 * Returns 0 if allocation failed (0 is not a valid block ID)
 */
uint16_t fs_alloc_sector(Storage *disk_p) {
  // First read the super block, setting dirty flag
  SuperBlock *sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
  uint16_t ret = 0;
  // If there are cached free values, then just get one
  if(sb_p->free_array.nfree != 0) {
    ret = sb_p->free_array.free[sb_p->free_array.nfree];
    sb_p->free_array.nfree--;
  } else {
    uint16_t free_list_head = sb_p->free_array.free[0];
    // If there is no next block, then we have exhausted free blocks
    if(free_list_head == FS_INVALID_SECTOR) {
      ret = FS_INVALID_SECTOR;
    } else {
      // We use this sector as the free sector, and copy its free list into
      // the super block
      ret = free_list_head;
      // Read the free list head, and copy the free array into the temp
      // object (because the sb may have been evicted)
      uint16_t *data_p = (uint16_t *)read_lba(disk_p, free_list_head);
      FreeArray free_array;
      memcpy(&free_array, data_p, sizeof(FreeArray));
      // Then read super block again, and copies the temp free array into it
      // as the new free array
      sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
      memcpy(&sb_p->free_array, &free_array, sizeof(FreeArray));
    }
  }

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
void fs_free_sector(Storage *disk_p, uint16_t sector) {
  SuperBlock *sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
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

  return;
}

/*
 * load_inode_sector() - This function loads the sector an inode is in
 *                       and returns the pointer to that inode
 *
 * Note that this function does not check whether the inode number is
 * valid or not (it may be out of range if programming error happens)
 *
 * If write_flag is 1, then we load the sector for write. Otherwise load it
 * for read.
 */
Inode *load_inode_sector(Storage *disk_p, uint16_t inode, int write_flag) {
  size_t sector_num = inode / context.inode_per_sector;
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
 */
SuperBlock *fill_inode_free_array(Storage *disk_p, SuperBlock *sb_p) {
  // Only call this function when the inode array is empty
  assert(sb_p->ninode == 0);
  // inode sector is just after the super block
  uint16_t current_sector = FS_SB_SECTOR + 1;
  // Number of inodes we have scanned
  int count = 0;
  uint16_t current_inode = 0;
  // It can hold 100 inodes
  uint16_t free_inode_list[FS_FREE_ARRAY_MAX];
  for(uint16_t i = 0;i < context.inode_sector_count;i++) {
    Inode *inode_p = (Inode *)read_lba(disk_p, current_sector);
    for(size_t j = 0;j < context.inode_per_sector;j++) {
      // If the inode is not in-use
      if((inode_p[j].flags & FS_INODE_IN_USE) == 0) {
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
  sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
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
uint16_t fs_alloc_inode(Storage *disk_p) {
  SuperBlock *sb_p = (SuperBlock *)read_lba(disk_p, FS_SB_SECTOR);
  uint16_t ret;
  // If the array is empty, we just fill it first
  if(sb_p->ninode == 0) {
    sb_p = fill_inode_free_array(disk_p, sb_p);
  }

  // If the inode list is still empty, then we could not find 
  // any more inodes, and return failure
  if(sb_p->ninode == 0) {
    ret = FS_INVALID_INODE;
  } else {
    sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
    // Note that here we decrement first and then get inode number
    sb_p->ninode--;
    ret = sb_p->inode[sb_p->ninode];
    // Load the sector that holds the inode, and make it dirty because we 
    // are writing into this inode
    Inode *inode_p = load_inode_sector(disk_p, ret, 1);
    assert((inode_p->flags & FS_INODE_IN_USE) == 0);
    // Clear its previous content
    memset(inode_p, 0x0, sizeof(Inode));
    // Mark it as in-use
    inode_p->flags |= FS_INODE_IN_USE;
  }

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
void fs_free_inode(Storage *disk_p, uint16_t inode) {
  SuperBlock *sb_p = (SuperBlock *)read_lba(disk_p, FS_SB_SECTOR);
  // If it is not full, we just use it. Otherwise we ignore the free
  // inode list in sb and directly mask off the flag
  if(sb_p->ninode != FS_FREE_ARRAY_MAX) {
    // Upgrade to write
    sb_p = (SuperBlock *)read_lba_for_write(disk_p, FS_SB_SECTOR);
    sb_p->inode[sb_p->ninode] = inode;
    sb_p->ninode++;
  }

  // Load the sector containing this inode, and set it as dirty
  Inode *inode_p = load_inode_sector(disk_p, inode, 1);
  // Mask off the inodes
  inode_p->flags &= (~FS_INODE_IN_USE);

  return;
}

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

void test_fs_init(Storage *disk_p) {
  info("Testing fs initialization...");
  // Note that we must put the super block on the given location
  fs_init(disk_p, disk_p->sector_count, FS_SB_SECTOR);
  // Fill the parameters
  load_context(disk_p);
  return;
}

void test_alloc_sector(Storage *disk_p) {
  info("Testing sector allocation...");

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
  while(1) {
    memset(sector_map, 
          0x00, 
          sizeof(uint8_t) * free_sector_count);

    uint16_t sector;
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
      }
    } while(sector != FS_INVALID_SECTOR);
    
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
      for(uint16_t i = free_sector_start;i < total_sector_count;i++) {
        fs_free_sector(disk_p, i);
      }
    } else if(round == 1) {
      for(uint16_t i = total_sector_count - 1;i >= free_sector_start;i--) {
        fs_free_sector(disk_p, i);
      }
    } else if(round == 2) {
      srand(time(NULL));
      for(int i = 0;i < free_sector_count;i++) {
        // [free_sector_start, total_sector_count)
        uint16_t start = \
          ((uint16_t)rand() % free_sector_count) + free_sector_start;
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
      break;
    }

    info("  ...Done");

    round++;
  } // while(1)

  free(sector_map);
  return;
}

void test_alloc_inode(Storage *disk_p) {
  info("Testing allocating inode...");

  const char *round_desp[] = {
    "Low to high",
    "High to low",
    "Random",
    "Verify"
  };
  
  // Preparing the array for recording which inode is allocated
  const size_t alloc_size = sizeof(uint8_t) * context.total_inode_count;
  uint8_t *flag_p = (uint8_t *)malloc(alloc_size);
  int round = 0;

  while(1) {
    memset(flag_p, 0x00, alloc_size);
    uint16_t inode;
    int count = 0;
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
        Inode *inode_p = load_inode_sector(disk_p, inode, 0);
        assert(inode_p->flags & FS_INODE_IN_USE);
      }
    } while(inode != FS_INVALID_INODE);

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
    info("  Free allocated sectors...");

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
        uint16_t start = (uint16_t)rand() % context.total_inode_count;
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
      break;
    }

    info("  ...Done");
    round++;
  }

  free(flag_p);
  return;
}

// This is a list of function call backs that we use to test
void (*tests[])(Storage *) = {
  test_lba_rw,
  test_buffer,
  test_fs_init,
  test_alloc_sector,
  test_alloc_inode,
  // This is the last stage
  free_mem_storage,
};

int main() {
  buffer_init();
  Storage *disk_p = get_mem_storage(2880);
  for(int i = 0;i < sizeof(tests) / sizeof(tests[0]);i++) {
    tests[i](disk_p);
  }

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

