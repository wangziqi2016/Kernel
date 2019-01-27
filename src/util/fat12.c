
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#define error_exit(fmt, ...) do { fprintf(stderr, "Error: " fmt, ##__VA_ARGS__); error_exit_or_jump(); } while(0);

typedef struct {
  uint8_t *p;
  size_t size;
} img_t;

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
  if(ret) error_exit("Cannot fseek to the begin of file")
  if(ret)
}

void img_free(img_t *img) {

}

int main() {
  return 0;
}