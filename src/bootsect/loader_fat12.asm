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
  xor si, si                                ; SI = index of the current entry
.body:
  mov ax, si
  mov cx, disk_param.size
  mul cx                                    ; DX:AX = offset within the table (ignore DX)
  mov bx, ax                                ; BX = offset of disk param entry
  add bx, [disk_mapping]                    ; BX = offset + base of disk mapping
.addr_hi           equ -8                   ; Local variables
.addr_lo           equ -10
.letter            equ -12
  push word 0                               ; [BP - 8] - Addr hi
  push word 26h                             ; [BP - 10] - Addr lo; Byte offset 0x26 (extended boot record)
  push word [bx + disk_param.letter]        ; [BP - 12] - Current letter of the disk
  mov ax, DISK_OP_READ                      ; Perform read
  call disk_op_word                         ; Read the first sector of the current disk
  jc .err                                   ; Do not clear stack because we read multiple words
  cmp al, 28h
  je .found
  cmp al, 29h
  je .found
.continue:
  ;add bx, disk_param.size
  inc si
  cmp si, [disk_mapping_num]
  jne .body
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
  xchg ax, bx                               ; BX = Ptr to the FAT12 param; AX = new pointer
  mov [bx + fat12_param.disk_param], ax     ; Store the back pointer
  xor ax, ax
  mov [bp + .addr_lo], ax                   ; Clear high bits of the address (we only use low 256 bytes for sure)
  mov di, .offset_table                     ; DI uses DS as implicit segment
  jmp .read_param
.offset_table:                              ; Defines the metadata we copy from sector 0
db 0dh, fat12_param.cluster_size
db 0eh, fat12_param.reserved
db 10h, fat12_param.num_fat
db 16h, fat12_param.fat_size
db 00h                                     ; Marks the end of table
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
  and si, 0ffh                              ; Only byte value
  inc di                                    ; DI = next entry
  mov [bx + si], ax                         ; Store data using BX + SI; Note that byte data may overwrite later entries
  pop si                                    ; Register restore
  jmp .read_param
.print_found:
  mov al, [bx + fat12_param.cluster_size]
  dec al
  test al, al                               ; Only supports 1 sector cluster
  jz .begin_print
  push fat12_init_inv_csz
  call video_printf_near                    ; Print error message and then goes BSOD
  jmp .err
.begin_print:
  xor ax, ax
  mov al, [bx + fat12_param.num_fat]
  push ax                                   ; Push number of FATs
  mul word [bx + fat12_param.fat_size]      ; DX:AX = Number of sectors for all (two) FATs
  add ax, [bx + fat12_param.reserved]
  push word [bx + fat12_param.fat_size]     ; Push FAT size
  push word [bx + fat12_param.reserved]     ; Push # of reserved sectors
  mov [bx + fat12_param.data_begin], ax     ; Begin LBA (from zero) of data section
  push ax                                   ; Push data begin
  mov ax, [bp + .letter]
  push ax                                   ; Push letter
  push fat12_init_str                       ; Push format string
  call video_printf_near
  add sp, 12
  jmp .continue
.err:                                       ; Jump here on error, stack must have an error message pushed
  push ds
  push fat12_init_err
  call bsod_fatal

; Returns the next sector given a sector
;   AX - The sector number
;   [BP + 4] - Disk letter
; Return:
;   AX - Next sector number. 0 means invalid sector b/c sector 0 must be boot record
;   BSOD on error. No invalid sector should be used to call this function
fat12_getnext:
  push bp
  mov sp, bp
  push bx
  mov ax, [bp + 4]
  call disk_getparam
  jc .err
  mov bx, ax
  mov bx, [bx + disk_param.fsptr]
.return:
  pop bx
  mov sp, bp
  pop bp
  ret
.err:
  push ds
  push fat12_getnext_err
  call bsod_fatal

fat12_init_str: db "FAT12 @ %c DATA BEGIN %u (RSV %u FAT SZ %u #FAT %u)", 0ah, 00h
fat12_init_err: db "FAT12 Init Error: %s", 0ah, 00h
fat12_init_inv_csz: db "Cluster size not 1", 0ah, 00h ; Failure reason, cluster size is greater than 1
fat12_getnext_err: db "FAT12 invarg getnext", 0ah, 00h

