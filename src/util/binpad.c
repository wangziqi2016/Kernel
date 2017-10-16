#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

/*
 * pad_binary_file() - Pads a binary file to a given length
 * 
 * - If file operation fails, just print error and exit with code 1
 * - If the file length is greater than the target length, print an error
 *   and exit with code 2;
 * - If finish successfully, exit with code 0;
 * - If overwrite flag is true, we simply overwrite that file; otherwise
 *   we print the output on stdout;
 * - All diagnostic outputs are printed on stderr
 * 
 * We overwrite the given file to pad it
 */
void pad_binary_file(const char *filename, 
                     uint8_t pad_value, 
                     size_t target_size,
                     int overwrite_flag) {
  struct stat file_status;
  int fd = open(filename, O_RDONLY);
  if(fd < 0) {
    perror(NULL);
    exit(1);
  }

  int ret = fstat(fd, &file_status);
  if(ret != 0) {
    perror(NULL);
    exit(1);
  }

  fprintf(stderr, "Basic file info\n");
  fprintf(stderr, "===============\n");
  fprintf(stderr, "File mode: 0x%X (regular? - %d)\n", 
          file_status.st_mode, S_ISREG(m));
  fprintf(stderr, "File size: %d\n", file_status.st_size);
  fprintf(stderr, "# of blocks: %d\n", file_status.st_blocks);

  ret = close(fd);
  if(ret != 0) {
    perror(NULL);
    exit(1);
  }

  return;
}

int main(int argc, char **argv) {

}