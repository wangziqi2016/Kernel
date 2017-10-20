import os
import sys
import glob


# This is the pattern for single file
SINGLE_FILE_PATTERN = None
# This is the name for combined files
COMBINED_FILE_NAME = None
CWD = None
LINE_NUMBER = None
# It maps the first line to file name
FILE_MAP = {}
# It maps the file name to starting line number in the
# combined file
LINE_MAP = {}

def init():
  """
  This function initializes the execution environment of this program. It
  does the following:
    (1) If argv[1] exists, then we use that to change the current working dir
    (2) If argv[2] exists, then we use that as the single file pattern
    (3) If argv[3] exists, then we use that as the file name of the combined 
        file
  Otherwise wrong number of arguments are provided
  """
  global CWD, SINGLE_FILE_PATTERN, COMBINED_FILE_NAME, LINE_NUMBER

  argv = sys.argv
  print argv
  if len(argv) != 5:
    print("Usage: python peek_line.py [working dir] [file pattern] [combined file name] [line # in combined file to peek]")
    sys.exit()
  
  os.chdir(argv[1])

  CWD = os.getcwd()
  SINGLE_FILE_PATTERN = argv[2]
  COMBINED_FILE_NAME = argv[3]
  LINE_NUMBER = int(argv[4])

  return

def build_file_map():
  """
  This function builds the file map by selecting files that matches
  a certain pattern, and then reading the first line of the file
  to determine their relative locations
  """
  file_list = glob.glob(SINGLE_FILE_PATTERN)
  if len(file_list) == 0:
    raise ValueError("There is no file under cwd: \"%s\"" % (CWD, ))
  
  for file_name in file_list:
    fp = open(file_name, "r")
    line = fp.readline().strip()
    if len(line) == 0:
      raise ValueError("The first line of file \"%s\" is empty!")
    elif line in FILE_MAP:
      old_file = FILE_MAP[line]
      raise ValueError("The line \"%s\" is identical for file \"%s\" and \"%s\"" % 
                        (line, old_file, file_name))
      
    FILE_MAP[line] = file_name
    
    fp.close()
  
  fp = open(COMBINED_FILE_NAME, "r")
  line_number = 1
  for line in fp:
    line = line.strip()
    if line in FILE_MAP:
      # If the line does come from a file then we know we have seen
      # the starting of a file
      file_name = FILE_MAP[line]
      # And then map the starting number to the file name
      LINE_MAP[line_number] = file_name
    
    line_number += 1

  fp.close()
  
  return

def peek_file():
  """
  This function peeks the file using a line number in the combined file and
  translate that to a line number in each individual files
  """
  current_min = None
  current_min_file = None
  for start_line, file_name in LINE_MAP.items():
    if LINE_NUMBER < start_line:
      continue

    delta = LINE_NUMBER - start_line
    if current_min is None or delta < current_min:
      current_min = delta
      current_min_file = file_name
  
  assert(current_min_file is not None)
  print("Line %d in file %s" % (current_min + 1, current_min_file))

  return

init()
build_file_map()
peek_file()