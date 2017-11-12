_loader_disk_start:
;
; loader_disk.asm - This file contains disk driver and I/O routine
;

; The maximum number of hardware devices we could support
DISK_MAX_DEVICE  equ 8
; The max number of times we retry for read/write failure
DISK_MAX_RETRY   equ 3
; The byte size of a sector of the disk
DISK_SECTOR_SIZE equ 512d

; Error code for disk operations
DISK_ERR_WRONG_LETTER   equ 1
DISK_ERR_INT13H_FAIL    equ 2
DISK_ERR_RESET_ERROR    equ 3
DISK_ERR_INVALID_BUFFER equ 4

; This defines the structure of the disk parameter table
struc disk_param
  ; The BIOS assigned number for the device
  .number: resb 1
  ; The letter we use to represent the device
  ; which requires a translation
  ; This letter - 'A' is the index of this element in the table
  .letter: resb 1
  .type:   resb 1
  .head:   resb 1
  .sector: resb 1
  .unused: resb 1
  .track:  resw 1
  ; These two are derived from the above parameters
  ; Capacity is in terms of sectors
  .capacity:            resd 1
  ; This is used to compute CHS
  .sector_per_cylinder: resw 1
  .size:
endstruc

; 16 sectors are cached in memory
DISK_BUFFER_MAX_ENTRY     equ 16d

; Constants defined for disk sector buffer
DISK_BUFFER_STATUS_INUSE  equ 01h
DISK_BUFFER_STATUS_DIRTY  equ 02h
DISK_BUFFER_STATUS_PINNED equ 04h

; These two are used as arguments for performing disk r/w
; via the common interface
DISK_OP_READ  equ 0201h
DISK_OP_WRITE equ 0301h

; This is the pointer value for denoting invalid pointer
; (used for maintaining the queue)
DISK_BUFFER_PTR_INV equ 0ffffh

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
  call disk_compute_param
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

  ; This function computes some frequently used parameters for all disks
  ; and store them in the corresponding entries of the disk parameter mapping
disk_compute_param:
  push bx
  push si
  push di
  mov si, [disk_mapping_num]
.body:
  test si, si
  je .return
  dec si
  ; Start from the last
  xor ax, ax
  mov al, 'A'
  add ax, si
  ; Save a copy of the disk letter in DI also
  mov di, ax
  push ax
  ; Need to check return value - although it should not fail in practice
  call disk_get_param
  mov bx, ax
  pop ax
  test bx, bx
  je .invalid_letter
  ; 1. Compute the capacity of the disk, in # of sectors
  ;   BX is the base address of the param table
  ;   DI is the letter we are doing computation for
  push di
  call disk_get_size
  pop cx
  ; Note that this function sets the CF if it fails
  jc .invalid_letter
  ; DX:AX contains the capacity in sectors
  mov [bx + disk_param.capacity], ax
  mov [bx + disk_param.capacity + 2], dx
  ; 2. Compute sector per cylinder which is frequently used during
  ;    CHS computation, and put it back to sector_per_cylinder
  mov al, [bx + disk_param.head]
  mov ah, [bx + disk_param.sector]
  ; Must use head + 1 as its count
  inc al
  mul ah
  mov [bx + disk_param.sector_per_cylinder], ax
  jmp .body
.return:    
  pop di
  pop si
  pop bx
  retn
.invalid_letter:
  ; We know DI saves the copy of disk letter
  push di
  push di
  push ds
  push disk_invalid_letter_str
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
  ; Current status is set to 0
  mov [bp + .CURRENT_STATUS], ax
  mov ah, 'A'
  ; We start from 0x00 (disk num) and 'A' (letter assignment)
  mov [bp + .CURRENT_DISK_NUMBER], ax
.body:
  ; ES:DI = 0:0 as required by INT13H
  xor ax, ax
  mov es, ax
  mov di, ax
  ; BIOS INT 13h/AH=08H to detect disk param
  mov ah, 08h
  mov dl, [bp + .CURRENT_DISK_NUMBER]
  ; It does not preserve any register value
  int 13h
  ; Can either because we finished enumarating floppy disks,
  ; harddisks, or a real error - jump to the routine to check
  jc .error_13h
  ; If the (current disk num & 0x7F) >= DH
  ; then we know the INT returned success but there is no disk actually
  mov al, [bp + .CURRENT_DISK_NUMBER]
  and al, 7fh
  cmp dl, al
  jle .error_13h
  ; Save these three to protect them
  push cx
  push dx
  mov ax, disk_param.size
  ; Allocate a system static data chunk
  ; if fail (CF = 1) just print error message
  call mem_get_sys_bss
  jc .error_unrecoverable
  ; Save this everytime
  mov [disk_mapping], ax
  ; AL = device type; BX = starting offset
  xchg ax, bx
  ; Save disk type
  mov [bx + disk_param.type], al
  pop dx
  pop cx
  ; Save head num
  mov [bx + disk_param.head], dh
  ; AX = CL[7:6]CH[7:0]
  mov al, ch
  mov ah, cl
  shr ah, 6
  ; Save number of tracks
  mov [bx + disk_param.track], ax
  and cl, 03fh
  ; Save number of sectors
  mov [bx + disk_param.sector], cl
  ; Finally save the disk num and letter assignment
  ; Note that since number and letter has the same layout, we 
  ; just move them using one mov inst
  mov ax, [bp + .CURRENT_DISK_NUMBER]
  mov [bx + disk_param.number], ax
  ; Register will be destroyed in this routine
  call .print_found
  ; Increment the current letter and device number
  inc byte [bp + .CURRENT_DISK_NUMBER]
  inc byte [bp + .CURRENT_DISK_LETTER]
  ; Also increament the number of mappings
  inc word [disk_mapping_num]
  ; Compare whether we have exceeded the value. If we do
  ; then report error
  cmp word [disk_mapping_num], DISK_MAX_DEVICE
  ja .error_too_many_disks
  jmp .body
.return:
  mov sp, bp
  pop bp
  pop bx
  pop di
  pop es
  retn
  ; Just prints what was found
  ; Do not save any register
.print_found:
  mov ax, [bx + disk_param.sector]
  push ax
  mov ax, [bx + disk_param.head]
  push ax
  mov ax, [bx + disk_param.track]
  push ax
  mov ax, [bp + .CURRENT_DISK_NUMBER]
  push ax
  mov al, [bp + .CURRENT_DISK_LETTER]
  push ax
  push disk_init_found_str
  call video_printf_near
  add sp, 12
  retn
  ; Just change the disk number and then try again
.finish_checking_floppy:
  mov al, 80h
  mov [bp + .CURRENT_DISK_NUMBER], al
  ; Also change the status
  mov ax, .STATUS_CHECK_HDD
  mov [bp + .CURRENT_STATUS], ax
  jmp .body
.error_13h:
  mov ax, [bp + .CURRENT_STATUS]
  cmp ax, .STATUS_CHECK_FLOPPY
  je .finish_checking_floppy
  cmp ax, .STATUS_CHECK_HDD
  jmp .return
.error_unrecoverable:
  push ax
  push ds
  push disk_init_error_str
  call bsod_fatal
.error_too_many_disks:
  ; Print the max # of disks and then return
  push word DISK_MAX_DEVICE
  push ds
  push disk_too_many_disk_str
  call bsod_fatal

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Disk Param Computation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; This function returns the raw byte size of a disk given its
  ; letter number
  ; Size is returned in DX:AX as 512 byte sectors since it may exceeds 
  ; the 16 bit limit
  ; Under the CHS addressing scheme, the maximum possible sector is 24 bit
  ;   [BP + 4] - Letter
  ; Return: Set CF if the letter is invalid
  ;         Clear CF is success
disk_get_size:
  push bp
  mov bp, sp
  push bx
  mov ax, [bp + 4]
  push ax
  call disk_get_param
  mov bx, ax
  test ax, ax
  pop ax
  je .return_fail
  ; 8 bit
  mov al, [bx + disk_param.head]
  inc al
  ; 6 bit
  mov ah, [bx + disk_param.sector]
  ; AX = head * sector
  mul ah
  mov cx, [bx + disk_param.track]
  inc cx
  ; DX:AX = head * sector * track, in 512 byte sectors
  mul cx
  clc
  jmp .return
.return_fail:
  stc
.return:  
  pop bx
  mov sp, bp
  pop bp
  retn

;%define disk_get_chs_debug

  ; This function returns the CHS representation given a linear sector ID
  ; and the drive letter
  ;   [BP + 4] - Device letter
  ;   [BP + 6][BP + 8] - Linear sector ID (LBA) in small endian
  ; Return:
  ;   DH = head
  ;   DL = device number (i.e. the hardward number)
  ;   CH = low 8 bits of cylinder
  ;   CL[6:7] = high 2 bits of cylinder
  ;   CL[0:5] = sector
  ; CF is clear when success
  ; CF is set when error
disk_get_chs:
  push bp
  mov bp, sp
  push bx
  mov ax, [bp + 4]
  push ax
  call disk_get_param
  add sp, 2
  test ax, ax
  je .return_fail
  mov bx, ax
  ; CX = sector per cylinder
  mov cx, [bx + disk_param.sector_per_cylinder]
  mov ax, [bp + 6]
  mov dx, [bp + 8]
  div cx
  ; Now AX = in-cylinder offset
  ;     DX = cylinder ID,
  ; after the exchange
  xchg ax, dx
  mov cl, [bx + disk_param.sector]
  div cl
  ; Now AH = sector offset (starting from 0)
  ;     AL = head ID
  ;     DX = cylinder ID
  inc ah
%ifdef disk_get_chs_debug
  ; Protect AX and CX
  push ax
  push dx
  movzx cx, ah
  push cx
  movzx cx, al
  push cx
  push dx
  push .test_string
  call video_printf_near
  add sp, 8
  pop dx
  pop ax
  jmp .after_debugging
.test_string: db "CHS = %x %y %y", 0ah, 00h
%endif
.after_debugging:
  ; Make the high 2 bits of CL the bit 8 and 9 of the cylinder number
  mov cl, dh
  shl cl, 6
  ; CH is the low 8 bits of the cylinder
  mov ch, dl
  ; Make DH the head
  mov dh, al
  ; Make the low 6 bits of CL the sector ID starting from 1
  or cl, ah
  ; DL is the device number. For floppy it is from 
  ; 0x00 and for HDD it is from 0x80
  mov dl, [bx + disk_param.number]
  clc
  jmp .return
.return_fail:
  stc
.return:
  pop bx
  mov sp, bp
  pop bp
  retn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Disk Buffer Management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; This function searches the buffer. If a sector of given LBA is found 
  ; then we return it. Otherwise, we read the sector from memory
  ; and create a new buffer by eviction or using empty buffers.
  ; If the LBA is found in the current buffer list, but it is dirty, this
  ; function does not write back
  ; disk_buffer_entry *_disk_get_sector(char letter, uint32_t lba, uint16_t command);
  ;   [BP + 4] - lower byte is the letter
  ;   [BX + 6][BP + 8] - LBA
  ;   [BP + 10] - a status word as special commands for the operation
  ;      If DISK_BUFFER_STATUS_DIRTY is set we set the dirty flag for write
  ; Return
  ;   The offset of the buffer object
_disk_get_sector:
  push bp
  mov bp, sp
  push si
  ; Load ES
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
  ; DX:AX is the lba, CL is the letter
  ; Note that this three will not be changed in the loop,
  ; but will be changed after the loop
  mov ax, [bp + 6]
  mov dx, [bp + 8]
  mov cl, [bp + 4]
  ; SI is the current buffer object
  mov si, [disk_buffer_head]
.body:
  cmp si, DISK_BUFFER_PTR_INV
  je .not_found
  ; First check letter
  cmp [es:si + disk_buffer_entry.letter], cl
  jne .continue
  cmp [es:si + disk_buffer_entry.lba], ax
  jne .continue
  cmp [es:si + disk_buffer_entry.lba + 2], dx
  jne .continue
  ; If there is a hit of the LBA and letter, we move it
  ; to the beginning of the queue
  ; If we use find_empty_buffer() then this has already been done
  call disk_buffer_access
  ; AX is not changed
  jmp .return
.continue:
  mov si, [es:si + disk_buffer_entry.next]
  jmp .body
.not_found:
  ; Allocate an empty buffer, and then read the data
  call disk_find_empty_buffer
  ; AX = SI = new buffer allocated
  mov si, ax
  ; Re-load LBA and letter, and write them into the buffer
  mov ax, [bp + 6]
  mov dx, [bp + 8]
  mov cl, [bp + 4]
  ; Write letter and LBA
  mov [es:si + disk_buffer_entry.letter], cl
  mov [es:si + disk_buffer_entry.lba], ax
  mov [es:si + disk_buffer_entry.lba + 2], dx
  ; Since we changed AX just now, so change it back
  mov ax, si
  ; Call the read routine with AX being the pointer to the buffer object
  call disk_buffer_read_lba
  test ax, ax
  jnz .read_fail
  ; When reaching this block, SI must be the data pointer
.return:
  ; If the dirty bit is set in the command word, we 
  ; also set the dirty bit for the buffer
  test word [bp + 10], DISK_BUFFER_STATUS_DIRTY
  jz .no_set_dirty
  or byte [es:si + disk_buffer_entry.status], DISK_BUFFER_STATUS_DIRTY
.no_set_dirty:
  ; Return result in AX
  mov ax, si
  pop si
  mov sp, bp
  pop bp
  retn
.read_fail:
  push ax
  push ds
  push disk_read_fail_str
  call bsod_fatal
  ; NEVER RETURNS
  ; -------------

  ; Loads the sector for read. Do not set dirty flag. 
  ;   [BP + 4] - lower byte is the letter
  ;   [BX + 6][BP + 8] - LBA
  ;   Return: Pointer to the sector data
disk_get_sector:
  push bp
  mov bp, sp
  ; Command
  push word 0
  ; LBA
  mov ax, [bp + 8]
  push ax
  mov ax, [bp + 6]
  push ax
  ; Letter
  mov ax, [bp + 4]
  push ax
  call _disk_get_sector
  ; DO NOT CLEAR STACK - WE HAVE THE FRAME
  ; Adjust the pointer to the data area
  add ax, disk_buffer_entry.data
  mov sp, bp
  pop bp
  retn

  ; Same as disk_get_sector, except that we set the dirty bit
disk_get_sector_for_write:
  push bp
  mov bp, sp
  ; Command
  push word DISK_BUFFER_STATUS_DIRTY
  mov ax, [bp + 8]
  push ax
  mov ax, [bp + 6]
  push ax
  mov ax, [bp + 4]
  push ax
  call _disk_get_sector
  ; DO NOT CLEAR STACK - WE HAVE THE FRAME
  ; Adjust the pointer to the data area
  add ax, disk_buffer_entry.data
  mov sp, bp
  pop bp
  retn

;%define disk_find_empty_buffer_debug
  ; This function returns an empty buffer from the buffer cache
  ; Currently we ignore the pinned flag (it is always advisory)
  ; If all entries are occupied, we evict a buffer and then
  ; return it
  ;   Return: AX = the pointer in 
  ; Note that the returned buffer will have VALID bit set to 1
  ; and modified set to 0. The LBA, disk letter and disk number must
  ; be set by the caller.
  ; This function cannot fail.
disk_find_empty_buffer:
  push es
  push bx
  push si
  ; Load the segment register
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
  ; Loop var
  mov si, [disk_buffer_size]
  ; BX must always hold the current disk buffer address
  mov bx, [disk_buffer]
.body:
  test si, si
  jz .not_found
  dec si
  ; It we found an invalid (empty) one then just return
  test byte [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_INUSE
  jz .return
  add bx, disk_buffer_entry.size
  jmp .body
  ; Before entering this, BX must contain the entry
.return:
  ; Mark it as valid, not dirty and not pinned
  mov byte [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_INUSE
  mov ax, bx
  ; Add to the head of the buffer
  ; AX is not changed by this function
  call disk_buffer_add_head
%ifdef disk_find_empty_buffer_debug
  ; Debug - print the index
  ; Save return value first
  push ax
  ; Use division to compute the index
  mov ax, bx
  sub ax, [disk_buffer]
  xor dx, dx
  mov cx, disk_buffer_entry.size
  div cx
  push dx
  push ax
  push .debug_index_str
  call video_printf_near
  add sp, 6
  pop ax
%endif
  pop si
  pop bx
  pop es
  retn
%ifdef disk_find_empty_buffer_debug
.debug_index_str: db "Index = %u (rem %u)", 0ah, 00h
%endif
.not_found:
  ; AX = evivted buffer (dirty flag may not be cleared)
  call disk_buffer_evict_lru
  mov bx, ax
  jmp .return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Queue Management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; This function returns the index of a buffer in the buffer pool
  ; given its pointer.
  ; If the pointer is invalid we jump to BSOD
  ; AX = pointer
  ; Return: AX = index; DX = remainder (should be 0)
disk_buffer_get_index:
  xor dx, dx
  sub ax, [disk_buffer]
  mov cx, disk_buffer_entry.size
  div cx
  test dx, dx
  jnz .invalid_ptr
  retn
.invalid_ptr:
  push ds
  push disk_invalid_ptr_to_index
  call bsod_fatal
  ; NEVER RETURNS
  ; -------------

  ; Prints current active buffers using their indices
disk_buffer_print:
  push es
  push si
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
  mov si, [disk_buffer_head]
  ; If the head is an inv ptr, then we just print
  ; a single word indicating that this is empty
  cmp si, DISK_BUFFER_PTR_INV
  je .print_empty
.body:
  cmp si, DISK_BUFFER_PTR_INV
  je .return
  ; AX holds the current pointer to the buffer object
  mov ax, si
  ; After this call, AX holds the index and DX is 0
  call disk_buffer_get_index
  ; Status byte
  mov dl, [es:si + disk_buffer_entry.status]
  push dx
  ; Index
  push ax
  push disk_buffer_print_format
  call video_printf_near
  add sp, 6
  ; Go to the next object
  mov si, [es:si + disk_buffer_entry.next]
  jmp .body
.print_empty:
  mov ax, disk_buffer_print_empty
  call video_putstr_near
.return:
  ; New line
  mov al, 0ah
  call putchar
  pop si
  pop es
  retn

  ; This function adds a buffer into the current queue
  ; This function implements the buffer replacement poloicy
  ;   1. If we choose to add to the end of the queue, and evict 
  ;      from the beginning, then we are implementing FIFO
  ;   2. If we choose to add to the beginning of the queue, and 
  ;      we always move buffers to the beginning of the queue, and
  ;      always evict from the end, then we are implementing LRU
  ; Currently we implement LRU
  ;   AX = pointer to the buffer that we need to add
  ; Return: 
  ;   Same AX
disk_buffer_add_head:
  ; We load ES with the large BSS segment
  push es
  push bx
  push si
  push MEM_LARGE_BSS_SEG
  pop es
  ; ES:BX = base of the current buffer
  ; ES:SI = base of the current head
  ; AX = constant for invalid pointer
  mov bx, ax
  mov ax, DISK_BUFFER_PTR_INV
  mov si, [disk_buffer_head]
  ; Check whether the head is 0xffff and if it is we will
  ; just link both head and tail onto the current buffer and return
  cmp si, ax
  je .empty_queue
  ; If the queue is not empty, we do the following:
  ;   1. Set the next of the current buffer to the current head
  ;   2. Set the prev of the current buffer to INV
  ;   3. Set the prev of the currenr head to the current buffer
  ;   4. Set the head to the current buffer
  mov [es:bx + disk_buffer_entry.next], si
  mov [es:bx + disk_buffer_entry.prev], ax 
  mov [es:si + disk_buffer_entry.prev], bx
  mov [disk_buffer_head], bx
  jmp .return
.empty_queue:
  ; Both head and tail point to the buffer
  mov [disk_buffer_head], bx
  mov [disk_buffer_tail], bx
  ; The next and prev both point to invalid pointer
  ; (AX is set before we jump here)
  mov [es:bx + disk_buffer_entry.next], ax
  mov [es:bx + disk_buffer_entry.prev], ax
.return:
  mov ax, bx
  pop si
  pop bx
  pop es
  retn

  ; This function removes the given buffer and moves it to the head
  ; of the queue. It should be accessed for every hit in the buffer object
  ; This is how we implement LRU
  ;   AX = buffer to be accessed
  ; Return: AX is not changed
disk_buffer_access:
  ; It returns the same thing in AX
  call disk_buffer_remove
  call disk_buffer_add_head
  retn

  ; This function flushes a buffer given the pointer
  ;   AX = Pointer to the buffer to be flushed
  ; Return: AX is unchanged
disk_buffer_flush:
  ; Remove it and then write back
  call disk_buffer_remove
  ; AX is not changed
  call disk_buffer_wb
  ; AX is not changed
  retn

  ; This function flushs all buffer until the linked list is empty
disk_buffer_flush_all:
  push si
.body:
  ; Re-load the var and check whether it is invalid pointer
  mov si, [disk_buffer_head]
  cmp si, DISK_BUFFER_PTR_INV
  je .return
  ; Evict the buffer, and return it to the empty buffer pool
  call disk_buffer_evict_lru
  jmp .body
.return:
  mov ax, DISK_BUFFER_PTR_INV
  mov [disk_buffer_head], ax
  mov [disk_buffer_tail], ax
  pop si
  retn

%define debug_disk_buffer_wb

  ; Write back a buffer if it is dirty
  ;   AX = The buffer to be tested and written back
  ; Return: Same AX
disk_buffer_wb:
  push es
  push bx
  push MEM_LARGE_BSS_SEG
  pop es
  mov bx, ax
  test byte [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_DIRTY
  jz .return
  ; AX is still be buffer address, so we write it back
  call disk_buffer_write_lba
  jc .evict_fail
%ifdef debug_disk_buffer_wb
  mov ax, bx
  xor dx, dx
  sub ax, [disk_buffer]
  mov cx, disk_buffer_entry.size
  div cx
  push ax
  push .debug_str
  call video_printf_near
  add sp, 4
%endif
  ; Before enter this BX is always the return value
.return:
  mov ax, bx
  pop bx
  pop es
  retn
.evict_fail:
  ; Print it first
  ;call disk_buffer_print
  push ds
  push disk_evict_fail_str
  ; Call the no clear version to keep the printed buffer
  call bsod_fatal
  ; NEVER RETURNS
  ;--------------
%ifdef debug_disk_buffer_wb
.debug_str: db "WriteBack %u", 0ah, 00h
%endif
  
  ; We evict the buffer from the tail of the linked list
  ; First check whether it is dirty, if it is then we write back
  ; If not then just move it to the head and return it
  ; 
  ; This function will NOT put the buffer at the beginning of the queue
  ; This function will NOT clear the dirty flag even if it is written back
  ; Return:
  ;   AX = Buffer that we have evicted (must be in the linked list)
disk_buffer_evict_lru:
  ; Remove it from the linked list
  mov ax, [disk_buffer_tail]
  ; This will first remove it from the linked list
  ; and then check the dirty bit. If dirty is on then write it back
  call disk_buffer_flush
  ; AX is unchanged
  retn

  ; This function removes a buffer object from the linked list
  ; We support removing from any position, including head and tail and middle
  ; and removing the only element
  ;   1. If there is only one element, we just reset the head and tail to INV
  ;   2. If we remove from the head, we need to move the head
  ;   3. If we remove from the tail, we need to move the tail
  ;   4. If we remove from the middle, we just remove it
  ;   AX = The pointer to the buffer to be removed
  ; Return:
  ;   AX = The pointer to the buffer we removed (i.e. the same as input)
disk_buffer_remove:
  ; ES:SI = head
  ; ES:DI = tail
  ; ES:BX = to be removed
  push es
  push bx
  push si
  push di
  push MEM_LARGE_BSS_SEG
  pop es
  mov bx, ax
  mov si, [disk_buffer_head]
  mov di, [disk_buffer_tail]
  mov ax, DISK_BUFFER_PTR_INV
  ; If the head is INV then we are trying to remove from 
  ; empty queue
  cmp si, ax
  je .error_empty_queue
  ; If head == tail, we are removing the only element
  cmp si, di
  je .remove_last_one
  cmp si, bx
  je .remove_head
  cmp di, bx
  je .remove_tail
.remove_middle:
  ; Do not move head and tail, but change the prev and next
  mov si, [es:bx + disk_buffer_entry.prev]
  mov di, [es:bx + disk_buffer_entry.next]
  ; Both SI and DI should be valid pointers, because we know 
  ; it is neither head nor tail
  ; SI->next = DI
  ; DI->prev = SI
  mov [es:si + disk_buffer_entry.next], di
  mov [es:di + disk_buffer_entry.prev], si
.return:
  ; Restore AX
  mov ax, bx
  pop di
  pop si
  pop bx
  pop es
  retn
.remove_head:
  ; Change head to its next, and then change the current head's prev to INV
  mov si, [es:si + disk_buffer_entry.next]
  mov [disk_buffer_head], si
  mov [es:si + disk_buffer_entry.prev], ax
  jmp .return
.remove_tail:
  mov di, [es:di + disk_buffer_entry.prev]
  mov [disk_buffer_tail], di
  mov [es:di + disk_buffer_entry.next], ax
  jmp .return
.remove_last_one:
  ; If the only element in the queue is the not the one we are removing
  ; then we jump to error
  mov si, bx
  jne .error_remove_invalid
  ; The queue is now empty, so just set it
  mov [disk_buffer_head], ax
  mov [disk_buffer_tail], ax
  jmp .return
.error_remove_invalid:
  push ds
  push disk_rm_invalid_buffer_str
  call bsod_fatal
  ; NEVER RETURNS
  ;--------------
.error_empty_queue:
  push ds
  push disk_rm_from_empty_queue_str
  call bsod_fatal
  ; NEVER RETURNS
  ;--------------

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Disk R/W
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Fast wrapper for reading LBA into a buffer
  ; It has the same erorr condition and return value as disk_buffer_op_lba
  ;   AX = Offset to the buffer entry
  ; Return:
  ;   AX = 0 if success; Otherwise error
disk_buffer_read_lba:
  push word DISK_OP_READ
  push ax
  call disk_buffer_op_lba
  add sp, 4
  retn

  ; Fast wrapper for writing LBA into a buffer
disk_buffer_write_lba:
  push word DISK_OP_WRITE
  push ax
  call disk_buffer_op_lba
  add sp, 4
  retn

  ; This function reads or writes LBA of a given disk.
  ; Note that we do not modify the queue in this function. The caller
  ; is responsible for maintaining the queue
  ;   1. If the operation is write, we also clear the dirty flag
  ;   [BP + 4] - The pointer to the buffer object for writing
  ;              The buffer must have its driver letter and LBA set
  ;   [BP + 6] - The opcode (0x0201 for read; 0x0301 for write)
  ; Return value in AX. Please refer to disk_op_lba
  ;   In addition, AX = DISK_ERR_INVALID_BUFFER if the buffer is "invalid"
  ;   DO NOT SET CF!
disk_buffer_op_lba:
  ; Move the return address down by 2 bytes
  ; and add 2 bytes for the argument
  push bp
  mov bp, sp
  push bx
  ; Load the segment
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
  mov bx, [bp + 4]
  ; Check whether the buffer is valid, if not return error
  test byte [es:bx + disk_buffer_entry.status], DISK_BUFFER_STATUS_INUSE
  jz .return_invalid_buffer
  ; Push LARGE_BSS:base + data offset as the buffer pointer
  push ax
  lea ax, [es:bx + disk_buffer_entry.data]  
  push ax
  mov ax, [es:bx + disk_buffer_entry.lba + 2]
  ; Push high and low word of LBA
  push ax
  mov ax, [es:bx + disk_buffer_entry.lba]
  push ax
  ; Push the letter
  mov al, [es:bx + disk_buffer_entry.letter]
  push ax
  ; Push the opcode
  mov ax, [bp + 6]
  push ax
  call disk_op_lba
  add sp, 12
  ; If there is an error then we can catch it
  ; AX != 0 means error
  test ax, ax
  jnz .return
  ; Keep AX == 0 below
  ; If it is write then we set modified flag
  cmp word [bp + 6], DISK_OP_WRITE
  jne .return
  ; Clear the dirty byte for a successful write operation
  and byte [es:bx + disk_buffer_entry.status], ~DISK_BUFFER_STATUS_DIRTY
  jmp .return
.return_invalid_buffer:
  mov ax, DISK_ERR_INVALID_BUFFER
.return:
  pop bx
  mov sp, bp
  pop bp
  retn

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
  call disk_get_chs
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
  call disk_get_param
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
disk_get_param:
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
disk_init_found_str:       db "%c: #%y Maximum C/H/S (0x): %x/%y/%y", 0ah, 00h
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

; This is the head of the evict queue (i.e. linked list of sector objects)
; We use 0xffff to represent empty pointer.
disk_buffer_head: dw DISK_BUFFER_PTR_INV
; This is the tail of the evict queue
disk_buffer_tail: dw DISK_BUFFER_PTR_INV