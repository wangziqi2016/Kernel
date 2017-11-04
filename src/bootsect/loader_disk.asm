_loader_disk_start:
;
; loader_disk.asm - This file contains disk driver and I/O routine
;

; The maximum numbre of hardware devices we could support
DISK_MAX_DEVICE equ 8

  ; This function detects all floppy and hard disks using BIOS routine
disk_init:
  cli

  ; Start from device number 0x80 
.fixed_disk_init:  
  sti
  retn
  
; This is an offset in the system segment to the start of the disk param table
; We allocate the table inside the system static data area to save space
; in the compiled object
disk_mapping: dw 0
; Number of elements in the disk mapping table
disk_mapping_num: dw 0