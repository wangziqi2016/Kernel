_loader_fat12_start:
;
; loader_fat12.asm - This file implements FAT12 file system driver
;
; NOTE: FAT12 file system only supports 16MB disk at a maximum. Using an LBA
; of 1 word is sufficient, because we can address 32MB. Using offset of 1 word
; is problematic because only 64KB can be addressed

struc fat12_param           ; This defines FAT12 file system metadata
  .disk_param:       resw 1 ; Back pointer to disk parameter
  .cluster_size:     resb 1 ; Number of sectors per cluster (Sector 1, 0x0D)
  .reserved:         resw 1 ; Number of reserved sectors including sector 1 (Sector 1, 0x0E)
  .num_fat:          resb 1 ; Number of FAT tables (Sector 1, 0x10)
  .fat_size:         resw 1 ; Number of sectors per FAT (Sector 1, 0x16)
  .data_begin:       resw 1 ; Offset of sector that data begins (from 0), derived from above values
  .padding:          resb 1 ; Padding
  .size:
endstruc

; Initialization. This must be called after disk_mapping and disk_buffer is setup 
; because we use disk buffered I/O to perform init
fat12_init:
  push bp
  mov bp, sp
  push bx                                   ; [BP - 2] - Reg saving
  push si                                   ; [BP - 4] - Reg saving
  push di                                   ; [BP - 6] - Reg saving
  mov bx, [disk_mapping]
  mov si, [disk_mapping_size]
.body:
.addr_hi           equ -8                   ; Local variables
.addr_lo           equ -10
.letter            equ -12
  push word 0                               ; [BP - 8] - Addr hi
  push word 26h                             ; [BP - 10] - Addr lo; Byte offset 0x26 (extended boot record)
  push word [bx + disk_mapping.letter]      ; [BP - 12] - Current letter of the disk
  mov ax, DISK_OP_READ                      ; Perform read
  call disk_op_word                         ; Read the first sector of the current disk
  jc .err                                   ; Do not clear stack because we read multiple words
  cmp ax, 28h
  je .found
  cmp ax, 29h
  je .found
.continue:
  add bx, disk_param.size
  dec si
  test si, si
  jnz .body
.return:
  pop di
  pop si
  pop bx
  mov sp, bp
  pop bp
  ret
.found:
  mov ax, fat12_param.size
  call mem_get_sys_bss                      ; Allocate a perameter entry for FAT 12
  jc .err                                   ; Usually means sys static mem runs out
  mov [bx + disk_param.fsptr], ax           ; Save it in the fsptr field of disk param
  mov bx, ax                                ; BX = Ptr to the FAT12 param
  xor ax, ax
  mov [bp + .addr_lo], ax                   ; Clear high bits of the address (we only use low 256 bytes for sure)
  mov di, .offset_table                     ; DI uses DS as implicit segment
  jmp .read_param
.offset_table:                              ; Defines the metadata we copy from sector 0
.db 0dh, fat12_param.cluster_size
.db 0eh, fat12_param.reserved
.db 10h, fat12_param.num_fat
.db 16h, fat12_param.fat_size
.db 00h                                     ; Marks the end of table
.read_param:
  mov al, [di]                              ; Offset within first sector
  inc di
  test al, al                               ; Check if this is zero, if true then finished
  jz .print_found                           ; Reached the end of table
  mov byte [bp + .addr_lo], al              ; Update address
  mov ax, DISK_OP_READ                      ; Call for read
  call disk_op_word
  jc .err
  push si                                   ; Register saving
  mov si, [di]                              ; SI = offset within FAT12 param entry
  inc di                                    ; DI = next entry
  mov [ds:bx + si], ax                      ; Store data using BX + SI
  pop si                                    ; Register restore
  jmp .read_param
.err:
  push ds
  push fat12_init_err
  call bsod_fatal

fat12_init_str: db "FAT12 @ %c BEGIN %U", 0ah, 00h
fat12_init_err: db "FAT12 Init Error", 0ah, 00h