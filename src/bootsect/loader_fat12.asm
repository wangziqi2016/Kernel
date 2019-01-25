_loader_fat12_start:
;
; loader_fat12.asm - This file implements FAT12 file system driver
;
; NOTE: FAT12 file system only supports 16MB disk at a maximum. Using an LBA
; of 1 word is sufficient, because we can address 32MB. Using offset of 1 word
; is problematic because only 64KB can be addressed

FAT12_DIR_LENGTH     equ 32 ; Byte size of directory record 
FAT12_DIR_SHIFT      equ 5  ; log2(FAT12_DIR_LENGTH)

struc fat12_param           ; This defines FAT12 file system metadata
  .disk_param:       resw 1 ; Back pointer to disk parameter
  .cluster_size:     resb 1 ; Number of sectors per cluster (Sector 1, 0x0D)
  .reserved:         resw 1 ; Number of reserved sectors including sector 1 (Sector 1, 0x0E)
  .num_fat:          resb 1 ; Number of FAT tables (Sector 1, 0x10)
  .root_size:        resw 1 ; Number of entries in the root (root cannot be extended, Sector 1, 0x11)
  .fat_size:         resw 1 ; Number of sectors per FAT (Sector 1, 0x16)
  .root_begin:       resw 1 ; Offset of sector that root begins (from 0), derived from above values
  .data_begin:       resw 1 ; Offset of sector that data begins (from 0), derived from above values
  .padding:          resb 1 ; Padding
  .letter:           resb 1 ; Assigned letter of the drive
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
  mov byte [bx + disk_param.fstype], \
    DISK_FS_FAT12                           ; Adding FS type explicitly
  xchg ax, bx                               ; BX = Ptr to the FAT12 param; AX = new pointer
  mov [bx + fat12_param.disk_param], ax     ; Store the back pointer
  mov al, [bp + .letter]                    ; AL = Letter
  mov [bx + fat12_param.letter], al         ; Stoer the letter for disk function calls
  xor ax, ax
  mov [bp + .addr_lo], ax                   ; Clear high bits of the address (we only use low 256 bytes for sure)
  mov di, .offset_table                     ; DI uses DS as implicit segment
  jmp .read_param
.offset_table:                              ; Defines the metadata we copy from sector 0
db 0dh, fat12_param.cluster_size
db 0eh, fat12_param.reserved
db 10h, fat12_param.num_fat
db 11h, fat12_param.root_size
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
  mov [bx + fat12_param.root_begin], ax     ; Begin LBA (from zero) of data section
  push ax                                   ; Push root directory begin
  mov cx, [bx + fat12_param.root_size]      ; CX = # of entries in the root
  shr cx, \
    DISK_SECTOR_SHIFT - FAT12_DIR_SHIFT     ; CX = # of sectors in the root (assume it is exact)
  add ax, cx
  mov [bx + fat12_param.data_begin], ax
  push ax                                   ; Push data begin sector
  mov ax, [bx + fat12_param.letter]
  push ax                                   ; Push letter
  push fat12_init_str                       ; Push format string
  call video_printf_near
  add sp, 14
  jmp .continue
.err:                                       ; Jump here on error, stack must have an error message pushed
  push ds
  push fat12_init_err
  call bsod_fatal

; Returns the next sector given a sector
;   AX - The sector number
;   [BP + 4] - Ptr to the current instance of FAT12 table
; Return:
;   AX - Next sector number. 0 means empty sector; 0xFFFF means end of chain and other
;   BSOD on error. No invalid sector should be used to call this function
fat12_getnext:
  push bp
  mov sp, bp
  push bx                                   ; [BP - 2] - Reg save
  push si                                   ; [BP - 4] - Reg save
  mov bx, [bp + 4]                          ; BX = Ptr to FAT12 param table
  cmp ax, 2                                 ; Cluster numbering begins at 2 (b/c 0x0000 means empty)
  jb .err
  mov si, [bp + fat12_param.disk_param]     ; SI = disk param ptr
  mov cx, [ds:si + disk_param.capacity]     ; CX = Low word of disk capacity. For FAT12 we know high word is 0
  sub cx, [bx + fat12_param.data_begin]
  inc cx
  inc cx                                    ; CX = data area sectors + 2
  cmp ax, cx
  jae .err                                  ; Note that AX begins at 2, and is relative to data area
  mov cx, ax
  and cx, 1                                 ; CX = odd/even bit
  shr ax, 1
  mov dx, ax                                ; DX = AX / 2
  add ax, ax                                ; AX = AX / 2 * 2
  add ax, dx                                ; AX = AX / 2 * 3
  add ax, cx                                ; AX = (AX / 2) * 3 + odd/even bit which is the sector number
  mov si, ax                                ; SI = Byte offset within FAT
  mov ax, [bx + fat12_param.reserved]
  mov dx, DISK_SECTOR_SIZE
  mul dx                                    ; DX:AX = Begin offset of FAT table
  add ax, si
  adc dx, 0                                 ; DX:AX = Begin offset of FAT entry (16 bit word)
  mov si, cx                                ; SI = Odd/even bit
  push dx                                   ; Arg offset high
  push ax                                   ; Arg offset low
  push word [bx + fat12_param.letter]       ; Arg letter
  mov ax, DISK_OP_READ
  call disk_op_word
  add sp, 6
  test si, si                               ; Zero means even, 1 means odd
  jz .even_sect
  shr ax, 12                                ; For odd sectors, use high 12 bits
  jmp .after_process
.even_sect:
  and ax, 0fffh                             ; For even sectors, use low 12 bits
.after_process:                             ; AX stores the next sector number
  cmp ax, 0ff0h                             ; Everything below 0x0FF0 is normal (in-use, free)
  jb .return
  xor ax, ax                                ; Otherwise it is invalid (end of chain, bad sect, etc.)
  dec ax                                    ; Return 0xFFFF
.return:
  pop si
  pop bx
  mov sp, bp
  pop bp
  ret
.err:
  push ds
  push fat12_getnext_err
  call bsod_fatal

fat12_init_str: db "FAT12 @ %c DATA %u ROOT %u (RSV %u FAT SZ %u #FAT %u)", 0ah, 00h
fat12_init_err: db "FAT12 Init Error: %s", 0ah, 00h
fat12_init_inv_csz: db "Cluster size not 1", 0ah, 00h ; Failure reason, cluster size is greater than 1
fat12_getnext_err: db "FAT12 invarg getnext", 0ah, 00h

