_loader_fat12_start:
;
; loader_fat12.asm - This file implements FAT12 file system driver
;
; NOTE: FAT12 file system only supports 16MB disk at a maximum. Using an LBA
; of 1 word is sufficient, because we can address 32MB. Using offset of 1 word
; is problematic because only 64KB can be addressed

FAT12_DIR_LENGTH     equ 32     ; Byte size of directory record 
FAT12_DIR_SHIFT      equ 5      ; log2(FAT12_DIR_LENGTH)
FAT12_INV_SECTOR     equ 0ffffh ; Invalid sector returned from getnext

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

struc fat12_dir           ; This defines FAT12 directory structure (standard 8.3 file name)
  .name:             resb 8 ; File name
  .suffix:           resb 3 ; Suffix
  .attr:             resb 1 ; File attribute
  .reserved:         resb 1 ; Reserved for windows NT
  .create_time_ms:   resb 1 ; Create time in 10ms resolution
  .create_time:      resw 1 ; Create time in sec-min-hour
  .create_date:      resw 1 ; Create date in day-month-year
  .last_accessed:    resw 1 ; Last accessed data in day-month-year
  .ea_index:         resw 1 ; Don't know what it is
  .modified_time:    resw 1 ; Last modified time in sec-min-hour
  .modified_date:    resw 1 ; Last modified date in day-month-year
  .cluster:          resw 1 ; First cluster (0 for special files and empty files)
  .size_byte:        resd 1 ; File size in bytes
  .size:                    ; Should be 32, there are constants defined for it
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
    DISK_SECTOR_SIZE_SHIFT - FAT12_DIR_SHIFT; CX = # of sectors in the root (assume it is exact)
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

; Opens a device for FAT12 access. A device can be opened multiple times, and there is 
; no need for a corresponding close
;   AX - The letter of the device
; Return:
;   AX - A transparent token used to access the file system; In practice it is pointer
;        to the disk_param struct
;   CX - Low word of the root token (used to access root directory)
;   DX - High word of the root token
;     (i.e. DX:CX is the byte offset of the root directory entry point)
;   CF is set if letter is invalid or device is not FAT12
fat12_open:
  push bx
  call disk_getparam                        ; AX has already been set
  jc .err                                   ; Invalid letter
  mov bx, ax                                ; BX = base address to disk_param. 
  cmp byte [bx + disk_param.fstype], \
    DISK_FS_FAT12                           ; If the fs type is not FAT12 report error
  jne .err
  mov bx, [bx + disk_param.fsptr]           ; Pointer to fat12_param
  mov dx, [bx + fat12_param.root_begin]     ; DX = Begin sector
  xor cx, cx                                ; DX:CX = Sector:Offset = RootSector:0
  mov ax, bx                                ; AX = Ptr to fat12_param
  pop bx
  clc
  ret
.err:
  pop bx
  stc
  ret

; Returns the next sector given a sector
;   AX - The clsuter number
;   [BP + 4] - Ptr to the current instance of FAT12 table
; Return:
;   AX - Next sector number, beginning from 0, relative to data area. 0xFFFF means other 
;        cases (free, invalid, end of chain, etc.).
;   BSOD on error. No invalid sector should be used to call this function
;   NOTE: Input value is clsuter number, return value is sector offset from data region
;         In order to get the cluster number we must add 2 to sector offset
fat12_getnext:
  push bp
  mov bp, sp
  push bx                                   ; [BP - 2] - Reg save
  push si                                   ; [BP - 4] - Reg save
  mov bx, [bp + 4]                          ; BX = Ptr to FAT12 param table
  cmp ax, 2                                 ; Cluster numbering begins at 2 (b/c 0x0000 means empty)
  jb .err
  mov si, [bx + fat12_param.disk_param]     ; SI = disk param ptr
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
  add ax, si                                ; Add byte offset within table
  adc dx, 0                                 ; DX:AX = Begin offset of FAT entry odd/even (16 bit word)
  mov si, cx                                ; SI = Odd/even bit
  push dx                                   ; Arg offset high
  push ax                                   ; Arg offset low
  push word [bx + fat12_param.letter]       ; Arg letter
  mov ax, DISK_OP_READ
  call disk_op_word
  jc .err                                   ; It will BSOD, do not need to clear stack
  add sp, 6
  test si, si                               ; Zero means even, 1 means odd
  jz .even_sect
  shr ax, 4                                 ; For odd sectors, use high 12 bits
  jmp .after_process
.even_sect:
  and ax, 0fffh                             ; For even sectors, use low 12 bits
.after_process:                             ; AX stores the next sector number
  cmp ax, 0ff0h                             ; Everything below 0x0FF0 is normal (in-use, free)
  jae .return_reserved
  cmp ax, 0002h                             ; Everything below 0x2 is reserved
  jb .return_reserved
  dec ax
.return_reserved_before_dec:
  dec ax                                    ; Minus 2 because cluster ID begins at 2
.return:
  pop si
  pop bx
  mov sp, bp
  pop bp
  ret
.return_reserved:
  xor ax, ax
  jmp .return_reserved_before_dec           ; The dec is shared
.err:
  push ds
  push fat12_getnext_err
  call bsod_fatal

; Reads a directory entry. This function takes a token that represents the current read position
; on the disk, and modifies the token for next read. The structure of the token is transparent
; to the caller.
; The destination buffer has the layout of fat12_dir. The caller is responsible for parsing the struct.
; Only valid directory entries are copied. They do not include entries beginning with 0x00 (free), 0xE5 (deleted)
; and 0x2E (. and .. entry)
;   [BP + 4] - The FAT12 token
;   [BP + 6] - Low word of the token (offset)
;   [BP + 8] - High word of the token (sector)
;   [BP + 10] - Offset of destination buffer
;   [BP + 12] - Segment of destination buffer
; Return:
;   AX = 0 if there are entries; Otherwise this is the last entry
;   CF is set if error; CF is cleared if success
fat12_readdir:
  push bp
  mov bp, sp
  push es                                   ; [BP - 2]
  push bx                                   ; [BP - 4]
  push si                                   ; [BP - 6]
  mov ax, LARGE_BSS
  mov es, ax
  mov si, [bp + 4]                          ; SI = Ptr to fat12_param
.lba_hi             equ -8                  ; Local var
.lba_lo             equ -10
.letter             equ -12
  xor ax, ax                                ; AX = 0
  push ax                                   ; [BP - 8] Arg LBA hi = AX = 0 b/c we assume FAT12 does not handle > 64K sectors
  push word [bp + 8]                        ; [BP - 10] Arg LBA lo
  push word [si + fat12_param.letter]       ; [BP - 12] Arg letter
.read_sector:
  call disk_insert_buffer                   ; After return AX = Ptr to disk buffer entry
  jc .err                                   ; Don't clear stack here
  add ax, disk_buffer_entry.data            ; AX = Ptr to buffer data area
  add ax, [bp + 6]                          ; AX = Ptr to current dir entry in the buffer
  mov bx, ax                                ; BX = Ptr to current dir entry in the buffer
.read_entry:
  ; TODO: CHECK VALID ENTRY
.continue:
  mov ax, fat12_dir.size
  add bx, ax                                ; To next entry in the sector
  add [bp + 6], ax                          ; Also modify the argument
  cmp [bp + 6], DISK_SECTOR_SIZE            ; Check if current read offset reached the end of the sector
  jne .read_entry                           ; If we has not reached end of sector then keep reading next entry
  xor ax, ax
  mov [bp + 6], ax                          ; Offset is cleared to zero - to the beginning of next sector, if any
  mov ax, [si + fat12_param.data_begin]     ; AX = Sector that data begins (i.e. non-root dir should be after this)
  cmp [bp + .lba_lo], ax                    ; Compare the root LBA with data area sector
  jb .next_sector_root                      ; If below then it is root and the area is consecutive
  mov ax, [bp + 8]                          ; AX = Current sector
  inc ax
  inc ax                                    ; AX = Current cluster (begin at 2)
  push si                                   ; Arg FAT12 token (ptr to fat12_param)
  call fat12_getnext                        ; Return next sector offset in data area (NOT cluster!)
  pop cx                                    ; Clear stack; CX is destroyed
  cmp ax, FAT12_INV_SECTOR                  ; Check validity
  je .ret_nomore                            ; If the next sectof of the dir is invalid just return
  add ax, [si + fat12_param.data_begin]     ; AX = LBA to next sector
  mov [bp + 8], ax
  mov [bp + .lba_lo], ax                    ; Update both arg and local var
  jmp .read_sector
next_sector_root:                           ; AX = data begin sector on entering this block
  inc [bp + 8]                              ; Modify next sector in return arg
  inc [bp + .lba_lo]                        ; Modify next sector we are about to read
  cmp [bp + .lba_lo], ax                    ; Compare the sector after increment
  je .ret_nomore                            ; If it equals the data region start then we reached the end of root
  jmp .read_sector
.return:                                    ; Normal case do not set CF and go here
  clc
  add sp, 6                                 ; This will reset CF
.return_after_clear_stack:                  ; Error case set CF and go here
  pop si
  pop bx
  pop es
  mov sp, bp
  pop bp
  ret
.err:
  add sp, 6
  stc                                       ; Set carry bit
  jmp .return_after_clear_stack
.ret_nomore:                                ; Jump to here if no more entry is in the directory
  xor ax, ax
  inc ax
  jmp .return
ret_found: 
  xor ax, ax
  jmp .return

fat12_init_str: db "FAT12 %c DATA %u ROOT %u (RSV %u FATSZ %u #FAT %u)", 0ah, 00h
fat12_init_err: db "FAT12 Init Error: %s", 0ah, 00h
fat12_init_inv_csz: db "Cluster size not 1", 0ah, 00h ; Failure reason, cluster size is greater than 1
fat12_getnext_err: db "FAT12 invarg getnext", 0ah, 00h
fat12_readdir_err: db "readdir invarg", 0ah, 00h

