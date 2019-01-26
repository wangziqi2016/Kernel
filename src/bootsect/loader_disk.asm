_loader_disk_start:
;
; loader_disk.asm - This file contains disk driver and I/O routine
;

%define DISK_DEBUG

DISK_MAX_DEVICE        equ 8      ; The maximum number of hardware devices we could support
DISK_MAX_RETRY         equ 3      ; The max number of times we retry for read/write failure
DISK_SECTOR_SIZE       equ 512    ; The byte size of a sector of the disk
DISK_SECTOR_SIZE_SHIFT equ 9      ; Number of bits that need to be shifted
DISK_SECTOR_SIZE_MASK  equ 01ffh  ; Mask that leaves only sector offset bits
DISK_FIRST_HDD_ID      equ 80h    ; The device ID of first HDD

; Error code for disk operations
DISK_ERR_WRONG_LETTER   equ 1    
DISK_ERR_INT13H_FAIL    equ 2
DISK_ERR_RESET_ERROR    equ 3
DISK_ERR_INVALID_LBA    equ 4

DISK_FS_NONE            equ 0
DISK_FS_FAT12           equ 1

struc disk_param    ; This defines the structure of the disk parameter table
  .number:   resb 1 ; The BIOS assigned number for the device
  .letter:   resb 1 ; The letter we use to represent the device, starting from 'A'; Also used as index
  .type:     resb 1 
  .fstype:   resb 1 ; Type of the FS
  .sector:   resw 1 ; # of sectors
  .head:     resw 1 ; # of heads
  .track:    resw 1 ; # of tracks
  .capacity: resd 1 ; Total # of sectors in linear address space; double word
  .fsptr:    resw 1 ; A pointer to the file system metadata
  .size:
endstruc

; 16 sectors are cached in memory
DISK_BUFFER_SIZE          equ 10h        ; 16 entries
DISK_BUFFER_SIZE_MASK     equ 000fh      ; Mask is 0x000F to extract the index bit

; Constants defined for disk sector buffer
DISK_BUFFER_STATUS_VALID  equ 0001h
DISK_BUFFER_STATUS_DIRTY  equ 0002h

; These two are used as arguments for performing disk r/w
; via the common interface
DISK_OP_READ              equ 0201h
DISK_OP_WRITE             equ 0301h

; This is the structure of buffer entry in the disk buffer cache
struc disk_buffer_entry
  .status:  resw 1                 ; Dirty/Valid
  .number:  resb 1                 ; BIOS numbering
  .letter:  resb 1                 ; The device letter
  .lba:     resd 1                 ; The LBA that this sector is read from
  .data:    resb DISK_SECTOR_SIZE  ; Sector data to be stored
  .padding: resw 1                 ; Avoid invalid read/write when accessing the last byte - DO NOT REMOVE
  .size:
endstruc

disk_init:
  cli                    ; Disable interrupt because we allocate memory during init
  call disk_probe        ; Probes disks and populate the disk parameter table
  call disk_buffer_init  ; Allocates a disk sector buffer at A20 memory region
  sti
  retn
  
; This function allocates buffer pool for disk sectors and initialize the buffer
disk_buffer_init:
  push es
  push bx
  push si
  mov ax, disk_buffer_entry.size
  mov cx, DISK_BUFFER_SIZE
  mul cx                          ; DX:AX is the total number of bytes required
  test dx, dx                     ; If overflows to DX then it is too large (> 64KB we cannot afford)
  jnz .buffer_too_large
  mov bx, ax                      ; Save the size to BX
  call mem_get_large_bss          ; Otherwise AX contains requested size
  jc .buffer_too_large            ; If allocation fails report error
  mov [disk_buffer], ax           ; Otherwise AX is the start address
  push bx
  push ax
  push disk_buffer_size_str
  call video_printf_near          ; Print the disk buffer info
  ;add sp, 6                      ; Moved to below
  push bx                         ; Length
  xor ax, ax
  push ax                         ; Value
  push word MEM_LARGE_BSS_SEG     ; Segment
  mov ax, [disk_buffer]
  push ax                         ; Offset
  call memset                     ; Sets the buffer space to zero
  add sp, 14                      ; Clear arg for both functions
  pop si
  pop bx
  pop es
  ret
.buffer_too_large:
  push dx
  push ax
  push ds
  push disk_buffer_too_large_str
  call bsod_fatal

; Enumerates FDDs and HDDs using INT13H. Disk parameters are allocated on the 
; system segment and stored as disk_mapping
disk_probe:
  push es
  push di
  push bx
  push bp
  mov bp, sp
  sub sp, 4
.curr_letter         equ -1            ; Local variables
.curr_number         equ -2
.curr_status         equ -4
.STATUS_CHECK_FLOPPY equ 0             ; Constants for the current disk probing status
.STATUS_CHECK_HDD    equ 1
  xor ax, ax
  mov [bp + .curr_status], ax          ; Current status is set to 0
  mov ah, 'A'
  mov [bp + .curr_number], ax          ; We start from 0x00 (disk num) and 'A' (letter assignment)
.body:
  xor ax, ax
  mov es, ax
  mov di, ax                           ; ES:DI = 0:0 as required by INT13H
  mov ah, 08h                          ; BIOS INT 13h/AH=08H to detect disk param
  mov dl, [bp + .curr_number]          ; DL is BIOS drive number, 7th bit set if HDD
  int 13h                              ; It does not preserve any register value
  jc .error_13h                        ; Either disk number non-exist or real error
  mov al, [bp + .curr_number]          ; Note that it is possible that this routine returns success even if the 
  and al, 7fh                          ;   number is invalid. In this case we compare DL (# of drives returned) with
  cmp dl, al                           ;   the ID of drives to see if it is the case
  jle .error_13h
  push cx                              ; Save CX, DX before function call
  push dx                              
  mov ax, disk_param.size              ; Reserve one slot for the detected drive (AX is allocation size)
  call mem_get_sys_bss
  pop dx
  pop cx
  jc .error_unrecoverable              ; Fail if CF = 1
  mov [disk_mapping], ax               ; Save this everytime since the system segment grows downwards
  xchg ax, bx                          ; AL = drive type; BX = starting offset (INT13H/08H returns drive type in BL)
  mov [bx + disk_param.type], al       ; Save disk type
  xor dl, dl                           
  xchg dh, dl                          ; DH is always zero, DL is the head number
  inc dx                               ; DX is the number of heads
  mov [bx + disk_param.head], dx       ; Save number of heads (returned by INT13H/08H)
  mov al, ch                           ; Move CL[7:6]CH[7:0] into AX and save as number of tracks; CL has higher 2 bits
  mov ah, cl
  shr ah, 6
  inc ax                               ; Store the # of tracks
  mov [bx + disk_param.track], ax      ; AH = CL >> 6 and AL = CH
  and cl, 03fh
  xor ch, ch                           ; Higher 8 bits are 0
  mov [bx + disk_param.sector], cx     ; Save number of sectors as (CL & 0x3F), i.e. mask off high two bits
  mul cl                               ; AX = CL * AL (# sector * # track)
  mul dx                               ; DX:AX = AX * DX (# sector * # track * # head)
  mov [bx + disk_param.capacity], ax
  mov [bx + disk_param.capacity + 2], dx ; Store this as capacity in terms of sectors
  mov ax, [bp + .curr_number]          ; Low byte number high byte letter
  mov [bx + disk_param.number], ax     ; Save the above info into the table
  mov byte [bx + disk_param.fstype], \
    DISK_FS_NONE                       ; Initialize fstype to zero
  call .print_found                    ; Register will be destroyed in this routine
  inc byte [bp + .curr_number]         ; Increment the current letter and device number
  inc byte [bp + .curr_letter]
  inc word [disk_mapping_num]          ; Also increment the number of mappings
  cmp word [disk_mapping_num], DISK_MAX_DEVICE ; Report error if too many drives
  ja .error_too_many_disks
  jmp .body
.return:
  mov sp, bp
  pop bp
  pop bx
  pop di
  pop es
  retn
.print_found:                           ; Print the drive just found using printf
  push word [bx + disk_param.capacity + 2]
  push word [bx + disk_param.capacity]  ; 32 bit unsigned little endian
  push word [bx + disk_param.sector]
  push word [bx + disk_param.head]
  push word [bx + disk_param.track]
  push word [bp + .curr_number]         ; High 8 bits will be ignored although we also pushed the letter with this
  xor ax, ax
  mov al, [bp + .curr_letter]
  push ax
  push disk_init_found_str
  call video_printf_near
  add sp, 16
  retn
.finish_checking_floppy: 
  mov byte [bp + .curr_number], DISK_FIRST_HDD_ID    ; Begin enumerating HDDs
  mov word [bp + .curr_status], .STATUS_CHECK_HDD    ; Also change the status such that on next INT13H fail we return
  jmp .body
.error_13h:                                          ; This can be a real error or just because we finished the current drive type
  cmp word [bp + .curr_status], .STATUS_CHECK_FLOPPY ; If we are checking floppy and see this then switch to enumerate HDD
  je .finish_checking_floppy                       
  jmp .return                                        ; Otherwise return because we finished enumerating all disks
.error_unrecoverable:
  push ax
  push ds
  push disk_init_error_str
  call bsod_fatal
.error_too_many_disks: ; Print the max # of disks and then die
  push word DISK_MAX_DEVICE
  push ds
  push disk_too_many_disk_str
  call bsod_fatal

; This function returns a pointer to the disk param block given a disk letter
;   AX - The disk letter (ignore high 8 bits)
; Return: 
;   AX = Address of the disk_param entry
; CF is set on failure. AX is set to DISK_ERR_WRONG_LETTER
disk_getparam:
  mov ah, al
  cmp ah, 'A'
  jb .return_invalid
  sub ah, 'A'
  cmp ah, [disk_mapping_num]
  jae .return_invalid        ; If ah - 'A' >= mapping num it is also invalid
  mov al, [disk_mapping_num] ; entry index = (mapping num - 1 - (letter - 'A'))
  sub al, ah
  dec al
  mov ah, disk_param.size
  mul ah                     ; Get the byte offset of the entry
  add ax, [disk_mapping]     ; Add with the base address
  clc
  retn
.return_invalid:
  stc
  mov ax, DISK_ERR_WRONG_LETTER
  retn

; This function returns the CHS representation given a linear sector ID
; and the drive letter
;   [BP + 4] - Device letter (ignore high 8 bits)
;   [BP + 6][BP + 8] - Linear sector ID (LBA) in small endian
; Return:
;   DH = head
;   DL = device number (i.e. the hardware number)
;   CH = low 8 bits of cylinder
;   CL[6:7] = high 2 bits of cylinder
;   CL[0:5] = sector
; CF is clear when success, AX is undefined
; CF is set when error, AX contains one of the following:
;   - DISK_ERR_WRONG_LETTER if letter is wrong
;   - DISK_ERR_INVALID_LBA if LBA is too large
disk_getchs:
  push bp
  mov bp, sp
  push ax                ; Local variable used as current sector (starting from 1, must not be more than 6 bits)
.curr_sector equ -2
  push bx
  mov ax, [bp + 4]       ; AX = Paremeter to the function
  call disk_getparam     ; Get disk parameter first
  jc .error_wrong_letter
  mov bx, ax             ; BX is the table entry
  mov dx, [bp + 8]       ; Next compare the input LBA and the maximum LBA
  mov ax, [bp + 6]       ;   DX:AX = Input LBA
  cmp dx, [bx + disk_param.capacity + 2]
  ja .error_invalid_lba  ; If higher word is larger then LBA is too large
  jne .body              ; Jump to body is higher word is less than capacity
  cmp ax, [bx + disk_param.capacity] 
  jae .error_invalid_lba ; Lower word must be capacity - 1 or less
.body:
  mov cx, [bx + disk_param.sector]  ; CX = number of sectors per track
  div cx                            ; DX = Sector (only DL, no more than 6 bits); AX = Next step;
  inc dx                            ; Note that sector begins at 1
  mov [bp + .curr_sector], dx       ; Save sector in the local var
  xor dx, dx                        ; DX:AX = Next step
  mov cx, [bx + disk_param.head]    ; CX = number of heads per cylinder
  div cx                            ; DX = Head; AX = track
  mov dh, dl                        ; DH = head
  mov dl, [bx + disk_param.number]  ; DL = BIOS number
  mov ch, al                        ; CH = low 8 bits of track
  shl ah, 6                         ; Shift lower 2 bits to highest 2 bits (<<= 6)
  mov cl, ah                        ; High 2 bits of CL is low 2 bits of AH
  or cl, [bp + .curr_sector]        ; Low 6 bits of CL is OR'ed with sector (we know sector must not be more than 6 bits)
.return:
  pop bx
  mov sp, bp
  pop bp
  ret
.error_invalid_lba:
  mov ax, DISK_ERR_INVALID_LBA
  stc
.error_wrong_letter:                ; AX is already the error code
  jmp .return

; Reads or writes a word from/into disk, given the byte offset. Supports maximum 4GB disk.
;   [BP + 4] - Device letter
;   [BP + 6][BP + 8] - Byte offset of the word, can be unaligned
;   [BP + 10] - Data for write; do not need this for read
;   AX - operation code; DISK_OP_READ/DISK_OP_WRITE
; Return:
;   AX stores the 16 bit word for read; Returns data just written for write
;   On error, CF and AX are set based on the same condition as disk_insert_buffer
disk_op_word:
  push bp
  mov bp, sp
  push es                               ; [BP - 2]
  push bx                               ; [BP - 4] - Note: Must clear arguments before restoring these two reg
  push word MEM_LARGE_BSS_SEG
  pop es                                ; Load ES as the segment of buffer
  push ax                               ; [BP - 6] - Operation code (R/W)
  push ax                               ; [BP - 8] - Buffer data
  push ax                               ; [BP - 10] - Offset
  mov ax, [bp + 8]                      ; Offset high
  mov cx, ax
  shr ax, DISK_SECTOR_SIZE_SHIFT        ; AX >>= 9 to shift out the lowest 9 bits into lower
  shl cx, 7                             ; CX = offset_hi << 7, high 9 bits are low 9 bits of lba high
  push ax                               ; [BP - 12]  lba_hi
  mov ax, [bp + 6]                      ; Offset low
  shr ax, DISK_SECTOR_SIZE_SHIFT        ; AX >>= 9 to shift out the offset bits
  or ax, cx
  push ax                               ; [BP - 14] lba_lo
  mov ax, [bp + 4]
  push ax                               ; [BP - 16] letter
.opcode      equ -6                     ; Local variables
.buffer_data equ -8                     ; The following two are local scratch pads
.offset      equ -10
.lba_hi      equ -12                    ; Note that stack layout below is exactly the same as the argument list
.lba_lo      equ -14                    ; ... that disk_insert_buffer accept
.letter      equ -16
  mov ax, [bp + 6]                      ; Offset low
  and ax, DISK_SECTOR_SIZE_MASK         ; Extract lowest 9 bits
  mov [bp + .offset], ax                ; ... and store as offset
  call disk_insert_buffer               ; Arguments have been set up
  jc .return_err                        ; We can directly use jc because stack is not cleared
  mov bx, ax                            ; Return value is in AX
  add bx, [bp +.offset]                 ; First add in-sector offset. We also add field offset below
  cmp word [bp + .opcode], DISK_OP_WRITE
  je .process_write_1                   ; Fall through to read
  mov ax, [es:bx + \
           disk_buffer_entry.data]      ; Read ES:BX + offset entry.data + logical offset (not .offset variable)
  jmp .after_1
.process_write_1:
  mov ax, [bp + 10]
  mov [es:bx + \
       disk_buffer_entry.data], ax      ; We can do this even at sector boundary b/c the buffer has padding
  sub bx, [bp +.offset]                 ; Reset BX to the head of the buffer
  or word [es:bx + \
      disk_buffer_entry.status], \
    DISK_BUFFER_STATUS_DIRTY            ; Set dirty bits
.after_1:
  cmp word [bp + .offset], 01ffh        ; If offset is not 511 then the read does not cross boundary
  jne .finish
  mov [bp + .buffer_data], ax           ; Save AX to local var (high byte is ignored) - for write this is ignored
  inc word [bp + .lba_lo]
  adc word [bp + .lba_hi], 0            ; Increment the 32 bit LBA by 1 using INC + ADC
  call disk_insert_buffer               ; Read second half
  jc .return_err                        ; Same as above
  mov bx, ax                            ; Return value is in AX
  cmp word [bp + .opcode], DISK_OP_WRITE
  je .process_write_2                   ; Fall through to read for the 2nd half
  mov ah, [es:bx + \
           disk_buffer_entry.data]      ; Read first byte of buffer data into AX high byte
  mov al, [bp + .buffer_data]           ; Read into AX low byte
  jmp .finish
.process_write_2:
  mov al, [bp + 11]                     ; This is the high byte
  mov [es:bx + \
       disk_buffer_entry.data], al      ; Just write first byte using the higher byte
  or word [es:bx + \
      disk_buffer_entry.status], \
    DISK_BUFFER_STATUS_DIRTY            ; Set dirty bits
  mov ax, [bp + 10]                     ; Return data just written
.finish:
  clc
  jmp .return_normal
.return_err:
  stc                                   ; Note that the add sp, 8 below will clear CF
.return_normal:
  add sp, 12                            ; Clear stack local variables (resets CF; we clc anyway to stress the point)
  pop bx
  pop es
  mov sp, bp
  pop bp
  ret

; Inserts an entry into the buffer, may evict an existing entry. If an empty entry is found,
; the LBA and letter is filled into that entry and data is loaded from disk. On eviction,
; if the buffer entry is dirty then the sector is written back
;   [BP + 4] - Device letter
;   [BP + 6][BP + 8] - Linear sector ID (LBA) in small endian
; Return:
;   AX points to the entry's begin address, and the entry is already filled with LBA and letter and is valid.
;     Dirty bit may or may not be set
;   On error, CF and AX are set based on the same condition as disk_op_lba
;   On error, the buffer is not affected and no invalid entry will be entered
disk_insert_buffer:
  push bp
  mov bp, sp
.empty_slot equ -2
  xor ax, ax
  push ax                       ; [BP + .empty_slot], if 0 then there is no empty slot (0 is not valid offset in this case)
  push es
  push bx
  push si                       ; SI counts the number of entries, break loop if this equals buffer size
  mov cx, [bp + 6]
  and cx, DISK_BUFFER_SIZE_MASK ; CX = Table index
  mov ax, disk_buffer_entry.size; Note that this is greater than 256
  mul cx                        ; DX:AX = Offset; Ignore DX because we know it must be < 64KB
  mov bx, ax
  add bx, [disk_buffer]         ; BX = table base + entry offset
  mov ax, cx                    ; AX = Table index
  xor si, si                    ; SI begins at 0
  push word MEM_LARGE_BSS_SEG
  pop es
  ;mov bx, [disk_buffer]         ; ES:BX = Address of buffer entries
  ;xor ax, ax
.body:
  cmp si, DISK_BUFFER_SIZE      ; Check whether we finished all entries
  je .try_empty                 ; If no matching entry is found then first try to claim empty then evict
  test word [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_VALID
  jnz .check_existing           ; If it is valid entry then check parameters
  mov [bp + .empty_slot], bx    ; Write down empty slot in local var for later use
  jmp .continue                 ; And then try next entry
.check_existing:
  mov cx, [bp + 4]              ; CX = disk letter
  cmp cl, [es:bx + disk_buffer_entry.letter]
  jne .continue                 ; Skip if letter does not match
  mov cx, [es:bx + disk_buffer_entry.lba]
  cmp cx, [bp + 6]
  jne .continue                 ; Skip if lower bytes do not match
  mov cx, [es:bx + disk_buffer_entry.lba + 2]
  cmp cx, [bp + 8]
  jne .continue                 ; Skip if higher bytes do not match
.return:                        ; If found matching entry then fall through and return
  mov ax, bx
.return_err:                    ; Do not change AX (which is the err code) on error
  pop si
  pop bx
  pop es
  mov sp, bp
  pop bp
  ret
.continue:
  inc si                          ; Update number of entries
  inc ax                          ; Update current index
  add bx, disk_buffer_entry.size  ; Update current entry pointer
  cmp ax, DISK_BUFFER_SIZE
  jne .body                       ; If AX has not reached the very end no wrap back
  xor ax, ax
  mov bx, [disk_buffer]           ; Wrap back - Set AX and BX
  jmp .body
.try_empty:                     ; Get here if all entries are checked and no matching is found 
  mov bx, [bp + .empty_slot]    ; BX = Either empty slot or 0x0000
  test bx, bx
  jz .evict                     ; If BX is not valid, then evict an entry (no empty slot)
.found_empty:                   ; Otherwise, fall through to use the empty slot
  or word [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_VALID ; Make the entry valid by setting the bit
  push es                                     ; 4th argument - Segment of data pointer
  lea ax, [bx + disk_buffer_entry.data]       ; Generate the address within the entry
  push ax                                     ; 4th argument - Offset of data pointer
  mov ax, [bp + 8]
  mov [es:bx + disk_buffer_entry.lba + 2], ax ; Copy higher 16 bits of LBA
  push ax                                     ; 3rd argument - LBA high 16 bits
  mov ax, [bp + 6]
  mov [es:bx + disk_buffer_entry.lba], ax     ; Copy lower 16 bits of LBA
  push ax                                     ; 3rd argument - LBA low 16 bits
  mov ax, [bp + 4]
  mov [es:bx + disk_buffer_entry.letter], al  ; Copy the letter; Note that we should only copy the low byte
  push ax                                     ; 2nd argument - Disk letter
  push word DISK_OP_READ                      ; 1st argument - Opcode for disk LBA operation
  ;push .str
  ;call video_printf_near                     ; Uncomment this to enable debug printing
  ;add sp, 2
  call disk_op_lba
  sbb cx, cx                                  ; Save CF bit in CX
  add sp, 12
  test cx, cx
  jnz .error_read_fail                        ; If read error just return with CF
  jmp .return
;.str: db "%u %c %U %x %x", 0ah, 00h          ; Uncomment this to enable debug printing
.evict:
  mov ax, [disk_last_evicted]     ; Use the previous eviction index to compute this one (just +1)
  inc ax
  and ax, DISK_BUFFER_SIZE_MASK   ; Potentially wrap back
  mov [disk_last_evicted], ax     ; Store it for next eviction
  mov cx, disk_buffer_entry.size
  mul cx                          ; DX:AX = offset into the table; We assume DX == 0 because we enforce this in init
  add ax, [disk_buffer]           ; Add with base address
  mov bx, ax                      ; BX = Address of entry to evict
  call disk_evict_buffer          ; This function assumes ES:BX points to the entry to be evicted
  jmp .found_empty                ; Now we have an empty entry on ES:BX
.error_read_fail:
  and word [es:bx + disk_buffer_entry.status], \
    ~(DISK_BUFFER_STATUS_VALID | \
      DISK_BUFFER_STATUS_DIRTY)   ; Clear dirty and valid bits if read reports an error
  stc                             ; Previous operation may reset CF
  jmp .return_err

; Evicts a disk buffer entry. This function also writes back data if the entry is dirty
; The returned buffer pointer in BX has both valid and dirty bits off
;   BX - The address of the buffer entry
;   ES - The large BSS segment
; Return:
;   ES:BX - The address of the buffer entry (unchanged)
;   AX may get destroyed
;   CF is undefined. BSOD if eviction I/O fails
disk_evict_buffer:
  test word [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_DIRTY
  jz .after_evict                             ; If non-dirty just clear the bits and return non-changed
  push es                                     ; Segment of data pointer (since we assume ES to be LARGE BSS)
  lea ax, [bx + disk_buffer_entry.data]       ; Generate address within the entry
  push ax                                     ; Offset (current BX) of data pointer
  mov ax, [es:bx + disk_buffer_entry.lba + 2]
  push ax                                     ; High 16 bits of LBA
  mov ax, [es:bx + disk_buffer_entry.lba]
  push ax                                     ; Low 16 bits of LBA
  mov ax, [es:bx + disk_buffer_entry.letter]
  push ax                                     ; Disk letter
  push word DISK_OP_WRITE                     ; Opcode for disk LBA operation
  call disk_op_lba                            ; We assume invalid entries will not be entered into buffer
  sbb cx, cx
  add sp, 12
  test cx, cx
  jnz .error_evict_fail                       ; ... and therefore if this fails it must be data corruption or code bug
.after_evict:
  and word [es:bx + disk_buffer_entry.status], \
    ~(DISK_BUFFER_STATUS_VALID | \
      DISK_BUFFER_STATUS_DIRTY)               ; Clear dirty and valid bits
  ret
.error_evict_fail:
  push ds
  push disk_evict_fail_str
  call bsod_fatal

%ifdef DISK_DEBUG

DISK_DEBUG_NONE      equ 0 ; Do nothing
DISK_DEBUG_EVICT     equ 1 ; Whether this function also evicts dirty buffers

; This function is for debugging purpose. Prints buffer status, LBA and letter
;   AX - One or more of the above constants to control behavior
disk_print_buffer:
  push es
  push bx
  push si
  push di
  mov di, ax                                   ; DI = options passed via AX
  mov bx, [disk_buffer]
  push word MEM_LARGE_BSS_SEG
  pop es                                       ; ES:BX = Buffer pointer
  xor si, si                                   ; SI = index on the buffer table
.body:
  cmp si, DISK_BUFFER_SIZE
  je .return
  mov ax, [es:bx + disk_buffer_entry.status]
  test ax, DISK_BUFFER_STATUS_VALID
  jz .after_evict
  test ax, DISK_BUFFER_STATUS_DIRTY
  jz .after_evict
  test di, DISK_DEBUG_EVICT
  jz .after_evict
  call disk_evict_buffer                       ; ES:BX has been set and will not be changed
.after_evict:
  mov ax, [es:bx + disk_buffer_entry.status]
  push ax
  mov ax, [es:bx + disk_buffer_entry.letter]
  push ax
  mov ax, [es:bx + disk_buffer_entry.lba + 2]
  push ax
  mov ax, [es:bx + disk_buffer_entry.lba]
  push ax
  push .str
  call video_printf_near
  add sp, 10
  inc si
  add bx, disk_buffer_entry.size
  jmp .body
.return:
  mov ax, 000ah
  call putchar
  pop di
  pop si
  pop bx
  pop es
  ret
.str: db "%U %c (%u), ", 00h
%endif

; This function reads or writes LBA of a given disk
; Note that we use 32 bit LBA. For floppy disks, if INT13H fails, we retry
; for three times. If all are not successful we just return fail
;   int disk_op_lba(int op, char letter, uint32_t lba, void far *buffer_data);
;   [BP + 4] - 8 bit opcode on lower byte (0x02 for read, 0x03 for write); 
;              8 bit # of sectors to operate on higher byte (should be 1)
;   [BP + 6] - Disk letter (ignore high 8 bits)
;   [BP + 8][BP + 10] - low and high word of the LBA
;   [BP + 12][BP + 14] - Far pointer to the buffer data
; Return value:
;   CF set if error occurs. AX contains the error code that can be one of the following:
;     - DISK_ERR_WRONG_LETTER if the disk does not exist
;     - DISK_ERR_INVALID_LBA if LBA is too large
;     - DISK_ERR_INT13H_FAIL if INT13H fails that is not the above reason
;     - DISK_ERR_RESET_ERROR if disk motor reset fails
disk_op_lba:
  push bp
  mov bp, sp
.retry_counter equ -2
  xor ax, ax
  push ax                               ; This is temp var retry counter
  push es
  push bx
  push si
.retry:
  mov ax, [bp + 10]
  push ax                               ; LBA high 16 bits
  mov ax, [bp + 8]
  push ax                               ; LBA low 16 bits
  mov ax, [bp + 6]
  push ax                               ; Disk letter
  call disk_getchs                      ; Returns CHS representation in DX and CX; This may return err code in AX
  sbb si, si                            ; Can't use CX b/c it is the register for returning
  add sp, 6
  test si, si
  jnz .return_err                       ; Both CF and AX are properly set, directly return
  mov ax, [bp + 14]
  mov es, ax
  mov bx, [bp + 12]                     ; Load ES:BX to point to the buffer
  mov ax, [bp + 4]                      ; AX = Opcode + number of sectors to read/write
  int 13h                               ; Read/Write the LBA on given disk drive
  jc .retry_or_fail                     ; Either retry or fail
  xor ax, ax
  clc
  jmp .return
.return_fail_reset_error:
  mov ax, DISK_ERR_RESET_ERROR
  jmp .return_err
.return_fail_int13h_error:
  mov ax, DISK_ERR_INT13H_FAIL
.return_err:
  stc
.return:
  pop si
  pop bx
  pop es
  mov sp, bp
  pop bp
  retn
.retry_or_fail:
  mov ax, [bp + .retry_counter]           ; AX = Current number of failures
  cmp ax, DISK_MAX_RETRY                  ; Compare to see if we exceeds maximum
  je .return_fail_int13h_error            ; If positive then report INT13H error
  inc word [bp + .retry_counter]          ; Increment the failure counter for next use
  mov ax, [bp + 6]                        ; AX = Disk letter
  call disk_getparam
  jc .return_err                          ; Both CF and AX are properly set
  mov bx, ax                              ; BX = pointer to the table
  test byte [bx + disk_param.number], 80h ; If the number has 7-th bit set then it is an HDD
  jnz .return_fail_int13h_error           ; Do not retry for HDD
  mov dl, [bx + disk_param.number]        ; Otherwise it is FDD and we can reset the motor
  xor ax, ax                              
  int 13h                                 ; INT13H/00H - Reset motor
  jc .return_fail_reset_error
  jmp .retry

disk_init_error_str:       db "Error initializing disk parameters (AX = 0x%x)", 0ah, 00h
disk_init_found_str:       db "%c: #%y Maximum C/H/S (0x): %x/%y/%y Cap %U", 0ah, 00h
disk_buffer_too_large_str: db "Disk buffer too large! (%U)", 0ah, 00h
disk_buffer_size_str:      db "Sector buffer begins at 0x%x; size %u bytes", 0ah, 00h
disk_too_many_disk_str:    db "Too many disks detected. Max = %u", 0ah, 00h
disk_evict_fail_str:       db "Evict fail", 0ah, 00h

disk_mapping:      dw 0 ; Offset in the system BSS segment to the start of the disk param table
disk_mapping_num:  dw 0 ; Number of elements in the disk mapping table
disk_buffer:       dw 0 ; This is the starting offset of the disk buffer
disk_last_evicted: dw DISK_BUFFER_SIZE - 1 ; Index of the last evicted buffer entry

