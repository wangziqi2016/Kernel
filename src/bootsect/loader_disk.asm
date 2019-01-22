_loader_disk_start:
;
; loader_disk.asm - This file contains disk driver and I/O routine
;


DISK_MAX_DEVICE   equ 8     ; The maximum number of hardware devices we could support
DISK_MAX_RETRY    equ 3     ; The max number of times we retry for read/write failure
DISK_SECTOR_SIZE  equ 512d  ; The byte size of a sector of the disk
DISK_FIRST_HDD_ID equ 80h   ; The device ID of first HDD

; Error code for disk operations
DISK_ERR_WRONG_LETTER   equ 1
DISK_ERR_INT13H_FAIL    equ 2
DISK_ERR_RESET_ERROR    equ 3
DISK_ERR_INVALID_LBA    equ 4

struc disk_param    ; This defines the structure of the disk parameter table
  .number:   resb 1 ; The BIOS assigned number for the device
  .letter:   resb 1 ; The letter we use to represent the device, starting from 'A'; Also used as index
  .type:     resb 1 
  .unused:   resb 1
  .sector:   resw 1 ; # of sectors
  .head:     resw 1 ; # of heads
  .track:    resw 1 ; # of tracks
  .capacity: resd 1 ; Total # of sectors in linear address space; double word
  .size:
endstruc

; 16 sectors are cached in memory
DISK_BUFFER_MAX_ENTRY     equ 16d

; Constants defined for disk sector buffer
DISK_BUFFER_STATUS_VALID  equ 01h
DISK_BUFFER_STATUS_DIRTY  equ 02h

; These two are used as arguments for performing disk r/w
; via the common interface
DISK_OP_READ  equ 0201h
DISK_OP_WRITE equ 0301h

; This is the structure of buffer entry in the disk buffer cache
struc disk_buffer_entry
  ; PINNED DIRTY INUSE
  .status:  resb 1
  ; The device ID
  .unused1: resb 1
  ; The device letter
  .letter:  resb 1
  .unused2: resb 1
  ; The LBA that this sector is read from
  .lba:     resd 1
  ; All valid entries form a linked list
  ; This is the next pointer for maintaining the queue of active buffer entries
  .next:    resw 1
  ; The previous 
  .prev:    resw 1
  ; Sector data to be stored
  .data:    resb DISK_SECTOR_SIZE
  .size:
endstruc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Disk Initialization
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; This function probes all disks installed on the system
  ; and then computes disk parameters
disk_init:
  ; Must disable all interrupts to avoid having non-consecutive disk 
  ; param table in the BSS segment
  cli
  call disk_probe
  call disk_buffer_init
  sti
  retn
  
  ; This function allocates buffer for disk sectors and initialize the buffer
disk_buffer_init:
  push es
  push bx
  push si
  mov ax, disk_buffer_entry.size
  mov cx, DISK_BUFFER_MAX_ENTRY
  mov [disk_buffer_size], cx
  ; DX:AX is the total number of bytes required for the buffer 
  mul cx
  ; If overflows to DX then it is too large
  test dx, dx
  jnz .buffer_too_large
  ; Save the size to BX
  mov bx, ax
  ; Otherwise AX contains requested size
  call mem_get_large_bss
  ; If this fails then we know allocation fails
  jc .buffer_too_large
  ; Otherwise AX is the beginning of the buffer
  mov [disk_buffer], ax
  ; Print
  push bx
  push ax
  push disk_buffer_size_str
  call video_printf_near
  add sp, 6
  ; Then iterate through the buffer to initialize its status
  ; Use SI as loop index
  mov si, [disk_buffer_size]
  ; Use ES:BX as the buffer cache index
  mov bx, [disk_buffer]
  ; Load ES with the large BSS segment
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
  ; AX value will be preserved
  xor ax, ax
.body:
  test si, si
  jz .after_init
  dec si
  ; Set status word to 0x00 (Valid) - must use ES:BX
  mov [es:bx + disk_buffer_entry.status], al
  ; Advance the pointer
  add bx, disk_buffer_entry.size
  jmp .body
.after_init:  
.return:
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

  ; This function detects all floppy and hard disks using BIOS routine
disk_probe:
  push es
  push di
  push bx
  push bp
  mov bp, sp
  sub sp, 4
.CURRENT_DISK_LETTER equ -1
.CURRENT_DISK_NUMBER equ -2
.CURRENT_STATUS      equ -4
.STATUS_CHECK_FLOPPY equ 0
.STATUS_CHECK_HDD    equ 1
  xor ax, ax
  mov [bp + .CURRENT_STATUS], ax       ; Current status is set to 0
  mov ah, 'A'
  mov [bp + .CURRENT_DISK_NUMBER], ax  ; We start from 0x00 (disk num) and 'A' (letter assignment)
.body:
  xor ax, ax
  mov es, ax
  mov di, ax                           ; ES:DI = 0:0 as required by INT13H
  mov ah, 08h                          ; BIOS INT 13h/AH=08H to detect disk param
  mov dl, [bp + .CURRENT_DISK_NUMBER]  ; DL is BIOS drive number, 7th bit set if HDD
  int 13h                              ; It does not preserve any register value
  jc .error_13h                        ; Either disk number non-exist or real error
  mov al, [bp + .CURRENT_DISK_NUMBER]  ; Note that it is possible that this routine returns success even if the 
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
  mov ax, [bp + .CURRENT_DISK_NUMBER]  ; Low byte number high byte letter
  mov [bx + disk_param.number], ax     ; Save the above info into the table
  call .print_found                    ; Register will be destroyed in this routine
  inc byte [bp + .CURRENT_DISK_NUMBER] ; Increment the current letter and device number
  inc byte [bp + .CURRENT_DISK_LETTER]
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
  push word [bp + .CURRENT_DISK_NUMBER] ; High 8 bits will be ignored although we also pushed the letter with this
  xor ax, ax
  mov al, [bp + .CURRENT_DISK_LETTER]
  push ax
  push disk_init_found_str
  call video_printf_near
  add sp, 16
  retn
.finish_checking_floppy: 
  mov byte [bp + .CURRENT_DISK_NUMBER], DISK_FIRST_HDD_ID ; Begin enumerating HDDs
  mov word [bp + .CURRENT_STATUS], .STATUS_CHECK_HDD      ; Also change the status such that on next INT13H fail we return
  jmp .body
.error_13h:                       ; This can be a real error or just because we finished the current drive type
  cmp word [bp + .CURRENT_STATUS], .STATUS_CHECK_FLOPPY ; If we are checking floppy and see this then switch to enumerate HDD
  je .finish_checking_floppy                       
  jmp .return                                      ; Otherwise return because we finished enumerating all disks
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

  ; This function returns the CHS representation given a linear sector ID
  ; and the drive letter
  ;   [BP + 4] - Device letter
  ;   [BP + 6][BP + 8] - Linear sector ID (LBA) in small endian
  ; Return:
  ;   DH = head
  ;   DL = device number (i.e. the hardware number)
  ;   CH = low 8 bits of cylinder
  ;   CL[6:7] = high 2 bits of cylinder
  ;   CL[0:5] = sector
  ; CF is clear when success
  ; CF is set when error, AX contains one of the following:
  ;   - DISK_ERR_WRONG_LETTER if letter is wrong
  ;   - DISK_ERR_INVALID_LBA if LBA is too large
disk_getchs:
  push bp
  mov bp, sp
  push ax                ; One local variable
.curr_sector equ -2
  push bx
  mov ax, [bp + 4]
  push ax
  call disk_getparam     ; Get disk parameter first
  pop cx                 ; Clear stack
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
  mov [bp + .curr_sector], dx       ; Save sector in the local var
  xor dx, dx                        ; DX:AX = Next step
  mov cx, [bx + disk_param.head]    ; CX = number of heads per cylinder
  div cx                            ; DX = Head; AX = track (might overflow)
  mov dh, dl                        ; DH = head
  mov dl, [bx + disk_param.number]  ; DL = BIOS number
  mov ch, al                        ; CH = low 8 bits of track
  shl ah, 6
  mov cl, ah                        ; High 2 bits of CL is low 2 bits of AH
  or cl, [bx + disk_param.sector]   ; Low 6 bits of CL is sector
.return:
  pop bx
  mov sp, bp
  pop bp
  ret
.error_wrong_letter:
  mov ax, DISK_ERR_WRONG_LETTER
  jmp .return
.error_invalid_lba:
  mov ax, DISK_ERR_INVALID_LBA
  jmp .return



  ; This function reads or writes LBA of a given disk
  ; Note that we use 32 bit LBA. For floppy disks, if INT13H fails, we retry
  ; for three times. If all are not successful we just return fail
  ;   int disk_op_lba(char letter, uint32_t lba, void far *buffer_data);
  ;   [BP + 4] - 8 bit opcode on lower byte (0x02 for read, 0x03 for write); 
  ;              8 bit # of sectors to operate on higher byte (should be 1)
  ;   [BP + 6] - Disk letter
  ;   [BP + 8][BP + 10] - low and high word of the LBA
  ;   [BP + 12][BP + 14] - Far pointer to the buffer data
  ; Return value:
  ;   CF cleared if success
  ;   CF set if error
  ; AX = 0 if success
  ; AX = DISK_ERR_WRONG_LETTER   if the letter is wrong
  ; AX = DISK_ERR_INT13H_FAIL    if INT 13h fails after 0 or more retries
disk_op_lba:
  push bp
  mov bp, sp
.RETRY_COUNTER equ -2
  xor ax, ax
  ; This is temp var retry counter
  push ax
  push es
  push bx
.retry:
  ; Push the same parameter into the stack
  mov ax, [bp + 10]
  push ax
  mov ax, [bp + 8]
  push ax
  mov ax, [bp + 6]
  push ax
  call disk_getchs
  add sp, 6
  jc .return_fail_wrong_letter
  ; Load ES:BX to point to the buffer
  mov bx, [bp + 14]
  mov es, bx
  mov bx, [bp + 12]
  ; Opcode + number of sectors to read/write
  mov ax, [bp + 4]
  ; After this line, AX, DX and CX cannot be changed
  ; as they contain information for performing disk I/O
  int 13h
  jc .retry_or_fail
  xor ax, ax
  clc
  jmp .return
.return_fail_wrong_letter:
  stc
  mov ax, DISK_ERR_WRONG_LETTER
  jmp .return
.return_fail_reset_error:
  stc
  mov ax, DISK_ERR_RESET_ERROR
  jmp .return
.return_fail_int13h_error:
  stc
  mov ax, DISK_ERR_INT13H_FAIL
.return:
  pop bx
  pop es
  mov sp, bp
  pop bp
  retn
  ; In this block we check whether the device is floppy and whether 
  ; we still can retry. If both are true, then we simply retry. Otherwise
  ; return read failure
.retry_or_fail:
  mov ax, [bp + .RETRY_COUNTER]
  cmp ax, DISK_MAX_RETRY
  je .return_fail_int13h_error
  inc word [bp + .RETRY_COUNTER]
  mov ax, [bp + 6]
  push ax
  call disk_getparam
  mov bx, ax
  pop ax
  jc .return_fail_wrong_letter
  ; If the number has 7-th bit set then it is a harddisk
  ; and we do not retry, just fail directly
  mov al, [bx + disk_param.number]
  and al, 80h
  jnz .return_fail_int13h_error
  ; Do a reset for floppy
  mov dl, [bx + disk_param.number]
  xor ax, ax
  int 13h
  jc .return_fail_reset_error
  jmp .retry

  ; This function returns a pointer to the disk param block
  ; of the given disk letter
  ;   [BP + 4] - The disk letter (low byte)
  ; Returns in AX; Returns NULL if letter is invalid
  ; We also set CF if fail; You can choose one to check
disk_getparam:
  push bp
  mov bp, sp
  mov al, [bp + 4]
  cmp al, 'A'
  jb .return_invalid
  sub al, 'A'
  ; If al - 'A' >= mapping num it is also invalid
  cmp al, [disk_mapping_num]
  jae .return_invalid
  mov ah, [disk_mapping_num]
  xchg ah, al
  sub al, ah
  dec al
  ; Before this AL is the index in the array of disk_param
  ; and the result of the mul is in AX
  mov ah, disk_param.size
  mul ah
  ; Add with the base address
  add ax, [disk_mapping]
  clc
  jmp .return
.return_invalid:
  xor ax, ax
  stc
.return:  
  mov sp, bp
  pop bp
  retn

disk_init_error_str:       db "Error initializing disk parameters (AX = 0x%x)", 0ah, 00h
disk_init_found_str:       db "%c: #%y Maximum C/H/S (0x): %x/%y/%y Cap %U", 0ah, 00h
disk_invalid_letter_str:   db "Invalid disk letter: %c (%y)", 0ah, 00h
disk_buffer_too_large_str: db "Disk buffer too large! (%U)", 0ah, 00h
disk_buffer_size_str:      db "Sector buffer begins at 0x%x; size %u bytes", 0ah, 00h
disk_evict_fail_str:       db "Evict fail", 0ah, 00h
disk_read_fail_str:        db "Read fail (%u)", 0ah, 00h
disk_too_many_disk_str:    db "Too many disks detected. Max = %u", 0ah, 00h
disk_rm_from_empty_queue_str:  db "Remove from empty queue", 0ah, 00h
disk_rm_invalid_buffer_str:    db "Remove invalid buffer", 0ah, 00h
disk_invalid_ptr_to_index: db "Invalid buffer pointer", 0ah, 00h
; Index (status)
disk_buffer_print_format:  db "%u,%y ", 00h
; Note that we deliberately do not put new line here
disk_buffer_print_empty:   db "(Empty)", 00h

; This is an offset in the system segment to the start of the disk param table
; We allocate the table inside the system static data area to save space
; in the compiled object
disk_mapping:     dw 0
; Number of elements in the disk mapping table
disk_mapping_num: dw 0
; This is the starting offset of the disk buffer
disk_buffer:      dw 0
; Number of entries in the buffer
disk_buffer_size: dw 0

