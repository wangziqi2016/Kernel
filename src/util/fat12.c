
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define UNITTEST // Uncomment this to compile the application

#define error_exit(fmt, ...) do { fprintf(stderr, "Error: " fmt, ##__VA_ARGS__); exit(1); } while(0);

#define read8(img, offset)  (*(uint8_t *)(img->p + offset))
#define read16(img, offset) (*(uint16_t *)(img->p + offset))
#define read32(img, offset) (*(uint32_t *)(img->p + offset))

#define FAT12_DIR_SIZE 32
#define FAT12_SECT_SIZE 512
#define FAT12_INV_SECT 0xFFFF

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
} fat12_t; 

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
  return fat12;
}

void fat12_free(fat12_t *fat12) { free(fat12); }

// Returns the next sector offset from the beginning of data area
// Note that the input is cluater which begins from 2. 
// Return: FAT12_INV_SECT if next is invalid; Sect offset otherwise.
sector_t fat12_getnext(fat12_t *fat12, cluster_t cluster) {
  if(cluster < 2 || cluster > fat12->cluster_num + 2) 
    error_exit("Cluster %d out of range\n", cluster);
  offset_t off = (fat12->reserved * FAT12_SECT_SIZE) + cluster / 2 * 3;
  sector_t sect;
  if(cluster % 2 == 0) sect = read16(fat12->img, off) & 0x0FFF; // Low 12 bit
  else sect = (read16(fat12->img, off + 1) >> 4); // High 12 bit
  if(sect < 2 || sect >= 0xFF0) return FAT12_INV_SECT; 
  return sect - 2;
}

#ifdef UNITTEST

img_t *img;
fat12_t *fat12;

void test_init() {
  printf("Reserved %d FAT size %d Root begin %d Data begin %d\n",
         fat12->reserved, fat12->fat_size, fat12->root_begin, fat12->data_begin);
  printf("Cluster num %d\n", fat12->cluster_num);
}

int main() {
  img = img_init("../../bin/testdisk.ima");
  printf("Image size: %ld\n", img->size);
  fat12 = fat12_init(img);
  test_init();
  img_free(img);
  fat12_free(fat12);
  return 0;
}

#else 

int main() {
  printf("Not implemented\n");
  return 0;
}

#endif