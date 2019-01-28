
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#define error_exit(fmt, ...) do { fprintf(stderr, "Error: " fmt, ##__VA_ARGS__); error_exit_or_jump(); } while(0);

#define read16(img, offset) (*(uint16_t *)(img->p + offset))
#define read32(img, offset) (*(uint32_t *)(img->p + offset))

typedef struct {
  uint8_t *p;
  size_t size;
} img_t;

typedef struct {
  int cluster_size;        // Number of sectors per cluster; Only supports 1
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
  int ret = fseek(fp, SEEK_END, 0);
  if(ret) error_exit("Cannot fseek to the end of file\n");
  img->size = ftell(fp);
  if(img->size == -1L) error_exit("Cannot ftell to obtain file size\n");
  ret = fseek(fp, SEEK_SET, 0);
  if(ret) error_exit("Cannot fseek to the begin of file\n");
  img->p = (uint8_t *)malloc(img->size);
  if(img->p == NULL) error_exit("Cannot allocate for the image file\n");
  ret = fread(img->p, 1, img->size, fp);
  if(ret != img->size) error_exit("fread fails to read entire image\n");
  ret = fclose(fp);
  if(ret) error_exit("fclose fails to close the file\n");
  return img;
}

void img_free(img_t *img) {
  free(img->p);
  free(img);
}

fat12_t *fat12_init(img_t *img) {
  fat12_t *fat12 = (fat12_t *)malloc(sizeof(fat12_t));
  if(fat12 == NULL) error_exit("Cannot allocate fat12_t\n");
  uint8_t sig = img->p[38];
  if(sig != 0x28 && sig != 0x29) error_exit("Not a valid FAT12 image (sig %u)\n", (uint32_t)sig);
  fat12->reserved = *(uint16_t *)(img->p + 14)
  return fat12;
}

void fat12_free(fat12_t *fat12) { free(fat12); }

int main() {
  return 0;
}