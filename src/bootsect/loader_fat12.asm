_loader_fat12_start:
;
; loader_fat12.asm - This file implements FAT12 file system driver
;
; NOTE: FAT12 file system only supports 16MB disk at a maximum. Using an LBA
; of 1 word is sufficient, because we can address 32MB. Using offset of 1 word
; is problematic because only 64KB can be addressed

struc fat12_param           ; This defines FAT12 file system metadata
  .disk_param:       resw 1 ; Back pointer to disk parameter

  .size:
endstruc

; Initialization. This must be called after disk_mapping and disk_buffer is setup 
; because we use disk buffered I/O to perform init
fat12_init:
  push bp
  mov bp, sp
  push bx                                   ; [BP - 2] - Reg saving
  mov bx, [disk_mapping]
  mov cx, [disk_mapping_size]
.check_fat12:
.addr_hi           equ -4                   ; Local variables
.addr_lo           equ -6
.letter            equ -8
  push word 0                               ; [BP - 4] - Addr hi
  push word 26h                             ; [BP - 6] - Addr lo; Byte offset 0x26 (extended boot record)
  push word [bx + disk_mapping.letter]      ; [BP - 8] - Current letter of the disk
  mov ax, DISK_OP_READ                      ; Perform read
  call disk_op_word                         ; Read the first sector of the current disk
  jc .err                                   ; Do not clear stack because we read multiple words
  cmp ax, 28h
  je .found
  cmp ax, 29h
  je .found
.continue:
  add bx, disk_param.size
  loop .check_fat12
  pop bx
  mov sp, bp
  pop bp
  ret
.found:
  mov ax, fat12_param.size
  call mem_get_sys_bss                      ; Allocate a perameter entry for FAT 12
  jc .err                                   ; Usually means sys static mem runs out
  mov [bx + disk_param.fsptr], ax           ; Save it in the fsptr field of disk param
.err:
  push ds
  push fat12_init_err
  call bsod_fatal

fat12_init_str: db "FAT12 @ %c BEGIN %U", 0ah, 00h
fat12_init_err: db "FAT12 Init Error", 0ah, 00h