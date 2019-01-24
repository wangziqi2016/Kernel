_loader_fat12_start:
;
; loader_fat12.asm - This file implements FAT12 file system driver
;

struc fat12_meta            ; This defines FAT12 file system metadata
  .disk_param:       resw 1 ; Back pointer to disk parameter
  .size:
endstruc

; Initialization. This must be called after disk_mapping and disk_buffer is setup 
; because we use disk buffered I/O to perform init
fat12_init:
  ret

