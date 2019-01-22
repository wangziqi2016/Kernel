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
  .padding:  resb 2 ; Make it 16 bytes
  .size:
endstruc

; 16 sectors are cached in memory
DISK_BUFFER_MAX_ENTRY     equ 16d

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
  .size:
endstruc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Disk Initialization
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; This function probes all disks installed on the system
  ; and then computes disk parameters
disk_init:
  cli                    ; Disable interrupt because we allocate memory during init
  call disk_probe        ; Probes disks and populate the disk parameter table
  call disk_buffer_init  ; Allocates a disk sector buffer at A20 memory region
  sti
  retn
  
; This function allocates buffer for disk sectors and initialize the buffer
disk_buffer_init:
  push es
  push bx
  push si
  mov ax, disk_buffer_entry.size
  mov cx, DISK_BUFFER_MAX_ENTRY
  mov [disk_buffer_size], cx      ; Store number of entry into the global var
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
;   AX - The disk letter (low byte)
; Return: 
;   AX = Address of the disk_param entry
; CF is set on failure. AX is undefined. The only reason of failure is invalid disk letter
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
.return:  
  retn
.return_invalid:
  stc
  jmp .return

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
; CF is clear when success, AX is undefined
; CF is set when error, AX contains one of the following:
;   - DISK_ERR_WRONG_LETTER if letter is wrong
;   - DISK_ERR_INVALID_LBA if LBA is too large
disk_getchs:
  push bp
  mov bp, sp
  push ax                ; One local variable
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
  mov [bp + .curr_sector], dx       ; Save sector in the local var
  xor dx, dx                        ; DX:AX = Next step
  mov cx, [bx + disk_param.head]    ; CX = number of heads per cylinder
  div cx                            ; DX = Head; AX = track
  mov dh, dl                        ; DH = head
  mov dl, [bx + disk_param.number]  ; DL = BIOS number
  mov ch, al                        ; CH = low 8 bits of track
  shl ah, 6
  mov cl, ah                        ; High 2 bits of CL is low 2 bits of AH
  or cl, [bp + .curr_sector]        ; Low 6 bits of CL is sector
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

; Checks whether a given LBA of a given letter exists in the buffer
;   [BP + 4] - Device letter
;   [BP + 6][BP + 8] - Linear sector ID (LBA) in small endian
; Return:
;   AX points to the entry's begin address if found. CF is clear
;   If not found, CF is set
disk_lookup_buffer:
  push bp
  mov bp, sp
  push es
  push bx
  mov es, MEM_LARGE_BSS_SEG
  mov bx, [disk_buffer]         ; ES:BX = Address of buffer entries
  xor ax, ax                    ; AX = current index
  mov cx, [bp + 4]              ; CX = disk letter
.body:
  cmp ax, [disk_buffer_size]    ; Check if we reached the end of the buffer pool
  je .return_notfound           ; Set CF and return
  test [bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_VALID
  jz .continue                  ; Skip if not valid
  cmp cl, [bx + disk_buffer_entry.letter]
  jne .continue                 ; Skip if letter does not match
  mov cx, [bx + disk_buffer_entry.lba]
  cmp cx, [BP + 6]
  jne .continue                 ; Skip if lower bytes do not match
  mov cx, [bx + disk_buffer_entry.lba + 2]
  cmp cx, [BP + 8]
  jne .continue                 ; Skip if higher bytes do not match
  clc                           ; If found, clear CF to indicate success
  mov ax, bx
  jmp .return                   ; Return value in AX which is the pointer to the entry
.continue:
  inc ax
  add bx, disk_buffer_entry.size
  jmp .body
.return:
  pop bx
  pop es
  mov sp, bp
  pop bp
  ret
.return_notfound:
  stc
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
  call disk_getparam
  mov bx, ax
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

