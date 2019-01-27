
# FAT12 File System Driver

This file describes FAT12 file system internals and our implementation of FAT12 driver. FAT12 is a trademark of 
Microsoft. We do not own any copyright of FAT12 design.

## FAT12 Detection

FAT12 detection is performed during component initialization. FAT12 initialization routine is called right after disk
initialization. During the initialization routine, 