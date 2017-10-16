#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

/*
 * print_usage() - Prints the usage string and exit
 */
void print_usage() {
  fprintf(stderr, "binpad - Padding binary files\n");
  fprintf(stderr, "=============================\n\n");
  fprintf(stderr, "Usage: binpad [input file] [target length] [optional args]...\n\n");
  fprintf(stderr, "-h/--help       Print this string\n");
  fprintf(stderr, "-o/--output     Specifies the output file; if not specified then print on stdout\n");
  fprintf(stderr, "-v/--value      Specifies the byte value to pad; if not then pad 0x00\n");
  fprintf(stderr, "\n");
  exit(0);
}

/*
 * pad_binary_file() - Pads a binary file to a given length
 * 
 * - If file operation fails, just print error and exit with code 1
 * - If the file length is greater than the target length, print an error
 *   and exit with code 2;
 * - If finish successfully, exit with code 0;
 * - If output_filename is not NULL, we write output to the given file.
 *   If the output file already exists it will be overwritten;
 *   Otherwise we just print on stdout
 * - All diagnostic outputs are printed on stderr
 * 
 * We overwrite the given file to pad it
 */
void pad_binary_file(const char *filename, 
                     uint8_t pad_value, 
                     size_t target_size,
                     const char *output_filename) {
  struct stat file_status;
  int fd = open(filename, O_RDWR);
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
          file_status.st_mode, S_ISREG(file_status.st_mode));
  fprintf(stderr, "File size: %ld\n", (long)file_status.st_size);
  fprintf(stderr, "# of blocks: %ld\n", (long)file_status.st_blocks);

  ret = close(fd);
  if(ret != 0) {
    perror(NULL);
    exit(1);
  }

  return;
}

/*
 * read_integer() - Reads an integer from a char * and verifies its correctness
 * 
 * The second argument is used to indicate the usage of this integer to 
 * print a more meaningful error message
 */
int read_integer(const char *p, const char *purpose) {
  char buffer[64];
  if(strlen(p) >= 64) {
    fprintf(stderr, "%s \"%s\" too long\n", purpose, p);
    exit(1);
  }

  int val = atoi(p);
  sprintf(buffer, "%d", val);
  if(strcmp(buffer, p) != 0) {
    fprintf(stderr, "%s \"%s\" is not valid\n", purpose, p);
    exit(1);
  }

  return val;
}

/*
 * get_param() - This function assumes that at argv[index + 1] location
 *               there is a parameter, and checks whether it is valid or not
 * 
 * The paramrter should not be NULL (which indicates the end of argv). It
 * should not start with '-' because it indicates next option. 
 * 
 * Return argv[index + 1] if all checks are passed.
 */
char *get_param(char **argv, int index) {
  char *p = argv[index + 1];
  if(p == NULL) {
    fprintf(stderr, "Unexpected end of input when parsing \"%s\"\n",
            argv[index]);
    exit(1);
  } else if(p[0] == '-') {
    fprintf(stderr, "Unexpected start of the next option when parsing \"%s\"\n",
            argv[index]);
    exit(1);
  }

  return p;
}

int main(int argc, char **argv) {
  if(argc < 3) {
    print_usage();
  }

  for(int i = 3;i < argc;i++) {
    char *arg = argv[i];
    if(strcmp(arg, "--help") == 0 || 
       strcmp(arg, "-h") == 0) {
        print_usage();
    }
  }

  // Index == 1: file name
  // Index == 2: Target length
  const char *filename = argv[1];
  int target_size = read_integer(argv[2], "Target size");

  const char *output_filename = NULL;
  int pad_value = 0x00;
  for(int i = 3;i < argc;i++) {
    char *arg = argv[i];
    if(strcmp(arg, "--output") == 0 || 
       strcmp(arg, "-o") == 0) {
      // Can be either out of bound or another option
      output_filename = get_param(argv, i);
    } else if(strcmp(arg, "--value") == 0 || 
              strcmp(arg, "-v") == 0) {
      pad_value = read_integer(get_param(argv, i), "Padded value");
      if(pad_value <= 0x00 || pad_value >= 0xFF) {
        fprintf(stderr, "Padded value must be within [0, 255]\n");
        exit(1);
      } 
    } else {
      // For unknown command, default is to print usage and exit
      print_usage();
    }
  }

  pad_binary_file(filename, target_size, pad_value, output_filename);

  return 0;
}