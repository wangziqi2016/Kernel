
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define UNITTEST // Uncomment this to compile the application

#define error_exit(fmt, ...) do { fprintf(stderr, "Error: " fmt, ##__VA_ARGS__); exit(1); } while(0);

#define read8(img, offset)  (*(uint8_t *)(img->p + offset))
#define read16(img, offset) (*(uint16_t *)(img->p + offset))
#define read32(img, offset) (*(uint32_t *)(img->p + offset))

#define FAT12_DIR_SIZE 32
#define FAT12_SECT_SIZE 512
#define FAT12_INV_SECT 0xFFFF
#define FAT12_NAME_SIZE 8
#define FAT12_SUFFIX_SIZE 3
#define FAT12_NAME83_SIZE 11

#define FAT12_ATTR_READONLY 0x01
#define FAT12_ATTR_HIDDEN   0x02
#define FAT12_ATTR_SYSTEM   0x04
#define FAT12_ATTR_SUBDIR   0x10    // Mask for subdirectory
#define FAT12_ATTR_LONGNAME 0x0F    // This is not a mask, but rather an indicator
#define FAT12_ATTR_FILE     0x00    // A regular file. Not a mask

#define FAT12_READDIR_USED   0x00
#define FAT12_READDIR_FREE   0x01

#define FAT12_SUCCESS 0
#define FAT12_DIREND   1       // No more entry in the directory
#define FAT12_INV_NAME 1       // Invalid 8.3 file name
#define FAT12_NOTFOUND 2       // File name not found in current dir
#define FAT12_NOTDIR   3       // Name is found but it is not a dir entry
#define FAT12_NOTFILE  4       // Name is found but it is not a file entry
#define FAT12_INV_OFF  5       // Invalid offset in file read
#define FAT12_INV_LEN  6       // Invalid length in file read (read pass file end)
#define FAT12_NOSPACE  7       // Disk or root directory is full
#define FAT12_NAME_EXISTS 8    // The entry with the same name already exists

typedef uint16_t cluster_t;
typedef uint16_t sector_t;
typedef uint32_t offset_t;

typedef struct {
  uint8_t *p;
  size_t size;
  int sect_num;            // Number of sectors
} img_t;

typedef struct {
  img_t *img;
  int cluster_size;        // Number of sectors per cluster; Only supports 1
  int cluster_num;         // Number of clusters (in data area, by def.)
  int fat_size;            // Number of sectors in a FAT
  int fat_num;             // Number of FAT in the image
  int reserved;            // Number of reserved sectors before the FAT (incl. bootsect)
  int root_size;           // Number of sectors for root directory
  int root_begin;          // Sector ID for root
  int data_begin;          // Sector ID for data
  sector_t cwdsect_origin; // Current dir sector when entering the dir (absolute)
  sector_t cwdsect;        // Current dir sector (absolute)
  offset_t cwdoff;         // Current dir offset
} fat12_t; 

typedef struct {
  char name[8];
  char suffix[3];
  uint8_t attr;
  uint8_t reserved;
  uint8_t create_time_ms;
  uint16_t create_time;
  uint16_t create_date;
  uint16_t access_date;
  uint16_t ea_index;
  uint16_t modified_time;
  uint16_t modified_date;
  cluster_t data;                // First cluster
  uint32_t size;                 // File size in bytes
} __attribute__((aligned(1), packed)) fat12_dir_t;

typedef struct {
  sector_t curr_sect;            // Current reading sector
  offset_t curr_offset;          // Current reading offset within the sector
  offset_t offset;               // Logical read offset
  size_t size;                   // File size (updated on write)
} fat12_file_t;

img_t *img_init(const char *filename) {
  img_t *img = (img_t *)malloc(sizeof(img_t));
  if(img == NULL) error_exit("Cannot allocate img_t\n");
  FILE *fp = fopen(filename, "rb");
  if(fp == NULL) error_exit("Cannot open file %s\n", filename);
  int ret = fseek(fp, 0, SEEK_END);
  if(ret) error_exit("Cannot fseek to the end of file\n");
  img->size = ftell(fp);
  if(img->size == -1L) error_exit("Cannot ftell to obtain file size\n");
  ret = fseek(fp, 0, SEEK_SET);
  if(ret) error_exit("Cannot fseek to the begin of file\n");
  img->p = (uint8_t *)malloc(img->size);
  if(img->p == NULL) error_exit("Cannot allocate for the image file\n");
  ret = fread(img->p, img->size, 1, fp);
  if(ret != 1) error_exit("fread fails to read entire image\n");
  ret = fclose(fp);
  if(ret) error_exit("fclose fails to close the file\n");
  if(img->size % FAT12_SECT_SIZE != 0) error_exit("Image size is not a multiple of %d\n", FAT12_SECT_SIZE);
  img->sect_num = img->size / FAT12_SECT_SIZE;
  return img;
}

void img_free(img_t *img) {
  free(img->p);
  free(img);
}

fat12_t *fat12_init(img_t *img) {
  fat12_t *fat12 = (fat12_t *)malloc(sizeof(fat12_t));
  if(fat12 == NULL) error_exit("Cannot allocate fat12_t\n");
  fat12->img = img;
  uint8_t sig = read8(img, 38);
  if(sig != 0x28 && sig != 0x29) error_exit("Not a valid FAT12 image (sig %u)\n", (uint32_t)sig);
  if(read16(img, 510) != 0xAA55) error_exit("Not a valid bootable media\n");
  fat12->cluster_size = read8(img, 13);
  if(fat12->cluster_size != 1) error_exit("Do not support large cluster (%d)\n", fat12->cluster_size);
  fat12->reserved = read16(img, 14);
  fat12->fat_num = read8(img, 16);
  fat12->fat_size = read16(img, 22);
  fat12->root_size = read16(img, 17) * FAT12_DIR_SIZE / FAT12_SECT_SIZE;
  fat12->root_begin = fat12->reserved + fat12->fat_size * fat12->fat_num; // Root is right after FAT
  fat12->data_begin = fat12->root_begin + fat12->root_size; // Data is right after root
  fat12->cluster_num = (img->sect_num - fat12->data_begin) / fat12->cluster_size;
  fat12->cwdsect_origin = fat12->cwdsect = fat12->root_begin; // Point to the first entry of root directory
  fat12->cwdoff = 0;
  return fat12;
}

void fat12_free(fat12_t *fat12) { 
  img_free(fat12->img);
  free(fat12); 
}

// Resets the directory iterator pointer to the origin
void fat12_reset_dir(fat12_t *fat12) { 
  fat12->cwdsect = fat12->cwdsect_origin; 
  fat12->cwdoff = 0;
}

// Returns the offset of the FAT entry of a given cluster number from the beginning of the disk
// Note that FAT begins with cluster 0 (first two entries not used and marked invalid) but 
// data area begins with cluster 2, first sector is always usable.
offset_t fat12_fataddr(fat12_t *fat12, cluster_t cluster) {
  if(cluster < 2 || cluster > fat12->cluster_num + 2) 
    error_exit("Cluster %d out of range\n", cluster);
  offset_t off = (fat12->reserved * FAT12_SECT_SIZE) + cluster / 2 * 3;
  return off + (offset_t)(cluster % 2);
}

// Returns the next sector offset from the beginning of data area
// Note that the input is cluster which begins from 2. Cluster starts at the data region
// Return: FAT12_INV_SECT if next is invalid; Sect offset from data region otherwise.
sector_t fat12_getnext(fat12_t *fat12, cluster_t cluster) {
  offset_t off = fat12_fataddr(fat12, cluster);
  sector_t sect = read16(fat12->img, off);
  if(cluster % 2 == 0) sect &= 0x0FFF; // Low 12 bit
  else sect >>= 4;                     // High 12 bit
  if(sect < 2 || sect >= 0xFF0) return FAT12_INV_SECT; 
  return sect - 2;
}

// Helper function that finds the next sector of a directory
// Special care must be taken for root because it is consecutive
// Return: 1 if reached the end of the dir
int fat12_readdir_next(fat12_t *fat12) {
  fat12->cwdoff = 0;
  if(fat12->cwdsect < fat12->data_begin) // Root directory
    return ++fat12->cwdsect == fat12->data_begin; // If next sect is data area then reached the end
  sector_t next = fat12_getnext(fat12, fat12->cwdsect - fat12->data_begin + 2); // Returns relative sect from data begin
  if(next == FAT12_INV_SECT) return FAT12_DIREND;
  fat12->cwdsect = next + fat12->data_begin;
  return FAT12_SUCCESS;
}

// Read the corresponding entry into the buffer
// Return: FAT12_DIREND if reached the end of the directory. The cwd will point
// to the first invalid byte after the current sector (i.e. offset will be sector size
// and sect will be the last sector in absolute value)
// If ret_free is set, this function ignores buffer and stops at seeing a free 
// entry. Otherwise it copies the next active entry into the given buffer.
int fat12_readdir(fat12_t *fat12, fat12_dir_t *buffer, uint8_t ret_free) {
  offset_t off;
  while(1) {
    if(fat12->cwdoff == FAT12_SECT_SIZE && fat12_readdir_next(fat12) == FAT12_DIREND) {
      //fat12_reset_dir(fat12); // Do not reset, must leave the cwd_sect in the current value
      return FAT12_DIREND;
    }
    off = fat12->cwdsect * FAT12_SECT_SIZE + fat12->cwdoff; // Offset to the first byte of the entry
    fat12->cwdoff += FAT12_DIR_SIZE;
    fat12_dir_t *dir = (fat12_dir_t *)&read8(fat12->img, off);
    if(ret_free) {
      if(dir->name[0] == 0xE5 || dir->name[0] == 0x00) break; // Return free entry
      else continue; // Do not check if the above condition is not met
    }
    if(dir->name[0] != 0x00 && /*dir->name[0] != 0x2E &&*/ dir->name[0] != 0xE5 && 
       dir->name[0] != 0x05 && dir->attr != FAT12_ATTR_LONGNAME) break;
  }
  if(ret_free != FAT12_READDIR_FREE) memcpy(buffer, &read8(fat12->img, off), FAT12_DIR_SIZE);
  return FAT12_SUCCESS;
}

// Converts a C string to 8.3 file format
// Returns FAT12_INV_NAME if name is not valid 8.3 format
// Note that this function copies name beginning with '.' unchanged
// No '\0' is appended to the end of the string
int fat12_to83(const char *dir_name, char *name83) {
  int len = 0;
  if(*dir_name == '.') {
    while(len < FAT12_NAME83_SIZE) {
      if(*dir_name == '\0') *name83++ = ' ';
      else *name83++ = *dir_name++;
      len++;
    }
  }
  while(len < FAT12_NAME_SIZE) {
    if(*dir_name == '.' || *dir_name == '\0') *name83++ = ' ';
    else *name83++ = toupper(*dir_name++);
    len++;
  }
  if(*dir_name != '.' && *dir_name != '\0') return FAT12_INV_NAME;
  if(*dir_name == '.') dir_name++;
  while(len < FAT12_NAME83_SIZE) {
    if(*dir_name == '\0') *name83++ = ' ';
    else *name83++ = toupper(*dir_name++);
    len++;
  }
  if(*dir_name != '\0') return FAT12_INV_NAME;
  return FAT12_SUCCESS;
}

// Search by name and return the entry in a directory buffer
//   dir_name is the name of the dir in name.suffix format
//     The length of name must not exceed 8 and suffix not 3
// Returns FAT12_INV_NAME if name is not valid 8.3 format
//         FAT12_NOTFOUND if name is not found
//         FAT12_SUCCESS if success
int fat12_findentry(fat12_t *fat12, const char *name, fat12_dir_t *dir_entry) {
  char name83[FAT12_NAME83_SIZE];
  if(fat12_to83(name, name83) == FAT12_INV_NAME) return FAT12_INV_NAME;
  fat12_reset_dir(fat12); // This moves the cursor to the first in the current dir
  while(fat12_readdir(fat12, dir_entry, FAT12_READDIR_USED) == FAT12_SUCCESS)
    if(memcmp(name83, dir_entry->name, FAT12_NAME83_SIZE) == 0) return FAT12_SUCCESS;
  return FAT12_NOTFOUND;
}

// Changes current sector and offset of the dir entry given the dir name
// Same input and return as fat12_findentry
int fat12_enterdir(fat12_t *fat12, const char *dir_name) {
  fat12_dir_t dir_entry;
  int ret = fat12_findentry(fat12, dir_name, &dir_entry);
  if(ret != FAT12_SUCCESS) return ret;
  if(dir_entry.attr & FAT12_ATTR_SUBDIR) {
    if(dir_entry.data == 0) fat12->cwdsect = fat12->root_begin; // If data is zero the dir must be root (no empty dir)
    else fat12->cwdsect = dir_entry.data + fat12->data_begin - 2;
    fat12->cwdsect_origin = fat12->cwdsect;
    fat12->cwdoff = 0;
    return FAT12_SUCCESS;
  }
  return FAT12_NOTDIR;
}

// Opens a file and returns the file descriptor
// Return:
//   FAT12_SUCCESS if success
//   FAT12_NOTFILE if name is found but it is not a file
//   FAT12_NOTFOUND name is not found in the current dir
int fat12_open(fat12_t *fat12, const char *filename, fat12_file_t *fd) {
  fat12_dir_t dir_entry;
  int ret = fat12_findentry(fat12, filename, &dir_entry);
  if(ret != FAT12_SUCCESS) return ret;
  if(dir_entry.attr & FAT12_ATTR_SUBDIR) return FAT12_NOTFILE;
  fd->curr_sect = dir_entry.data + fat12->data_begin - 2;  // This can be zero which means empty file
  fd->curr_offset = fd->offset = 0;    // Always begin from offset 0 
  fd->size = dir_entry.size;           // Always check this field before reading
  return FAT12_SUCCESS;
}

int fat12_read(fat12_t *fat12, fat12_file_t *fd, offset_t len, void *buffer) {
  int invalid_len = (fd->offset + len >= fd->size); // Whether the read should be truncated
  if(invalid_len) len = fd->size - fd->offset;      // Truncate the length to not exceed file end
  char *p = buffer;        // Copy position
  offset_t remains = len;
  while(remains) {
    offset_t sect_len = FAT12_SECT_SIZE - fd->curr_offset;
    offset_t disk_offset = fd->curr_sect * FAT12_SECT_SIZE + fd->curr_offset;
    if(remains <= sect_len) {
      fd->offset += remains;
      fd->curr_offset += remains;
      memcpy(p, &read8(fat12->img, disk_offset), remains);
      remains = 0;
      break;
    }
    memcpy(p, &read8(fat12->img, disk_offset), sect_len);
    remains -= sect_len;
    p += sect_len;
    fd->offset += sect_len;
    fd->curr_offset = FAT12_SECT_SIZE; // Move logical pointer to sector end
    sector_t next_sect = fat12_getnext(fat12, fd->curr_sect - fat12->data_begin + 2); // Get next sector
    //printf("Next %u\n", next_sect);
    if(next_sect != FAT12_INV_SECT) {
      fd->curr_sect = next_sect + fat12->data_begin;
      fd->curr_offset = 0;
    } else { break; }
  }
  return invalid_len ? FAT12_INV_LEN : FAT12_SUCCESS;
}

//-------------- The following is added to support modification to the file system

// Sets the cluster's next to a given cluster
void fat12_setnext(fat12_t *fat12, cluster_t cluster, cluster_t next) {
  offset_t off = fat12_fataddr(fat12, cluster);
  sector_t sect = read16(fat12->img, off);
  next &= 0xFFF;
  if(cluster % 2 == 0) sect |= next; // Low 12 bit
  else sect |= (next << 4);          // High 12 bit
  *(&read16(fat12->img, off)) = sect;
  return;
}

// Allocate one sector for use. Return the sector ID relative to data area. Caller should convert it
// to cluster ID when storing into data field of directory
// Return: FAT12_INV_SECT if allocation fails
sector_t fat12_alloc_sect(fat12_t *fat12) {
  int sense = 0; // This flips between 0 and 1
  offset_t curr_off = fat12->reserved * FAT12_SECT_SIZE;
  offset_t fat_end_offset = curr_off + fat12->fat_size * FAT12_SECT_SIZE;
  sector_t sect = 0;  // Sector to be allocated
  while(curr_off < fat_end_offset) {
    sector_t entry;
    if(sense == 0) {
      entry = read16(fat12->img, curr_off) & 0x0FFF;
      curr_off++;
    } else {
      entry = read16(fat12->img, curr_off) >> 4;
      curr_off += 2;
    }
    //printf("Sect %u entry 0x%X\n", sect, entry);
    if(entry == 0) return sect;
    sense = 1 - sense;
    sect++;
  }
  return FAT12_INV_SECT;
}

// Add one new entry to the current directory, can be file or directory
// Return:
//   FAT12_INV_NAME if name is invalid
//   FAT12_NOSPACE  if there is no space left on the disk to create entry
//   FAT12_NAME_EXISTS if there is a name collision
int fat12_new(fat12_t *fat12, const char *filename, uint8_t attr) {
  fat12_dir_t entry;
  char name83[FAT12_NAME83_SIZE];
  int search = fat12_findentry(fat12, filename, &entry);
  if(search == FAT12_INV_NAME) return FAT12_INV_NAME;         // Invalid name for new entry
  else if(search == FAT12_SUCCESS) return FAT12_NAME_EXISTS;  // Name already exists
  fat12_reset_dir(fat12);   // Move to the head of disk entry
  if(fat12_readdir(fat12, NULL, FAT12_READDIR_FREE) == FAT12_DIREND) {
    if(fat12->cwdsect == fat12->data_begin) return FAT12_NOSPACE; // Root directory is full
    sector_t new_sect = fat12_alloc_sect(fat12); // Returns the sector relative to data area
    if(new_sect == FAT12_INV_SECT) return FAT12_NOSPACE; // No more free sector on the disk
    cluster_t new_cluster = new_sect + 2; // Convert sector to cluster
    cluster_t last_cluster = fat12->cwdsect - fat12->data_begin + 2; // Current dir's last cluster
    fat12_setnext(fat12, last_cluster, new_cluster); // Link to the last cluster
    fat12_setnext(fat12, new_cluster, 0xFF0);        // Mark the end of the linked list
    memset(&read8(fat12->img, (new_sect + fat12->data_begin) * FAT12_SECT_SIZE), 0x00, FAT12_SECT_SIZE);
    fat12->cwdsect = new_sect + fat12->data_begin;   // Change the cwd to the new location
    fat12->cwdoff = 0;
  }
  fat12_to83(filename, name83); // This must succeed because find entry returns
  fat12_dir_t *new_entry = (fat12_dir_t *)&read8(fat12->img, fat12->cwdsect * FAT12_SECT_SIZE + fat12->cwdoff);
  memcpy(new_entry->name, name83, FAT12_NAME83_SIZE);
  new_entry->attr = attr;
  new_entry->size = 0;
  new_entry->data = 0;
  if(attr & FAT12_ATTR_SUBDIR) {
    sector_t new_dir_sect = fat12_alloc_sect(fat12); // Sector from beginning of data area
    if(new_dir_sect == FAT12_INV_SECT) {
      new_entry->name[0] = 0x0; // Mark the new entry just created as invalid
      return FAT12_NOSPACE;
    }
    memset(&read8(fat12->img, (new_dir_sect + fat12->data_begin) * FAT12_SECT_SIZE), 0x00, FAT12_SECT_SIZE);
    new_entry->data = new_dir_sect + 2; // It takes cluster
    new_entry->size = FAT12_SECT_SIZE;
  }
  return 0;
}

#ifdef UNITTEST

img_t *img;
fat12_t *fat12;

void test_init() {
  printf("========== test_init ==========\n");
  printf("Reserved %d FAT size %d Root begin %d Data begin %d\n",
         fat12->reserved, fat12->fat_size, fat12->root_begin, fat12->data_begin);
  printf("Cluster num %d\n", fat12->cluster_num);
  printf("Pass!\n");
}

void test_readdir() {
  printf("========== test_readdir ==========\n");
  fat12_dir_t buffer;
  while(fat12_readdir(fat12, &buffer, FAT12_READDIR_USED) == FAT12_SUCCESS) {
    printf("%.11s    %u\n", buffer.name, buffer.size);
  }
  printf("Pass!\n");
}

void test_to83() {
  printf("========== test_to83 ==========\n");
  char name83[FAT12_NAME83_SIZE]; int ret;
  ret = fat12_to83("Makefile", name83);
  printf("\"%.*s\" ret = %d\n", FAT12_NAME83_SIZE, name83, ret);
  ret = fat12_to83("name1", name83);
  printf("\"%.*s\" ret = %d\n", FAT12_NAME83_SIZE, name83, ret);
  ret = fat12_to83("name1.exe", name83);
  printf("\"%.*s\" ret = %d\n", FAT12_NAME83_SIZE, name83, ret);
  ret = fat12_to83("name2.db", name83);
  printf("\"%.*s\" ret = %d\n", FAT12_NAME83_SIZE, name83, ret);
  ret = fat12_to83("name3.abcd", name83);
  printf("\"%.*s\" ret = %d\n", FAT12_NAME83_SIZE, name83, ret);
  ret = fat12_to83("name3toolong.x", name83);
  printf("\"%.*s\" ret = %d\n", FAT12_NAME83_SIZE, name83, ret);
  printf("Pass!\n");
}

void test_enterdir() {
  printf("========== test_enterdir ==========\n");
  int ret;
  ret = fat12_enterdir(fat12, "testdir");
  printf("ret = %d\n", ret);
  printf("========== Case 1 ==========\n");
  test_readdir();
  ret = fat12_enterdir(fat12, ".");
  printf("ret = %d\n", ret);
  printf("========== Case 2 ==========\n");
  test_readdir();
  ret = fat12_enterdir(fat12, "..");
  printf("ret = %d\n", ret);
  printf("========== Case 3 ==========\n");
  test_readdir();
  printf("Pass!\n");
}

void test_read() {
  printf("========== test_read ==========\n");
  fat12_file_t fd;
  char *buffer = (char *)malloc(64 * 1024); // 64KB buffer
  int ret = fat12_open(fat12, "bootsect.asm", &fd);
  if(ret != FAT12_SUCCESS) error_exit("Open failed\n");
  fat12_read(fat12, &fd, 1026, buffer);
  buffer[1026] = '\0';
  puts(buffer);
  printf("--------------------- sect %u off %u logical off %u\n", 
         fd.curr_sect, fd.curr_offset, fd.offset);
  fat12_read(fat12, &fd, 1028, buffer);
  buffer[1028] = '\0';
  puts(buffer);
  printf("--------------------- sect %u off %u logical off %u\n", 
         fd.curr_sect, fd.curr_offset, fd.offset);
  printf("Pass!\n");
  return;
}

void test_alloc_sect() {
  printf("========== test_alloc_sect ==========\n");
  for(int i = 0;i < 10;i++) {
    fat12_alloc_sect(fat12);
  }
  printf("Pass!\n");
  return;
}

int main() {
  img = img_init("../../bin/testdisk.ima");
  printf("Image size: %ld\n", img->size);
  fat12 = fat12_init(img);
  test_init();
  test_readdir();
  test_to83();
  test_enterdir();
  test_read();
  test_alloc_sect();
  fat12_free(fat12);     // This also frees the image file
  return 0;
}

#else 

int main() {
  printf("Not implemented\n");
  return 0;
}

#endif