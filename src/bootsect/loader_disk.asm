_loader_disk_start:
;
; loader_disk.asm - This file contains disk driver and I/O routine
;

; The maximum numbre of hardware devices we could support
DISK_MAX_DEVICE equ 8

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
  .capacity:            resd 1
  .sector_per_cylinder: resw 1
  .size:
endstruc

  ; This function probes all disks installed on the system
  ; and then computes disk parameters
disk_init:
  ; Must disable all interrupts to avoid having non-consecutive disk 
  ; param table in the BSS segment
  cli
  call disk_probe
  call disk_compute_param
  sti
  retn
  
  ; This function computes some frequently used parameters for all disks
  ; and store them in the corresponding entries of the disk parameter mapping
disk_compute_param:
  cli
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
  
.return:    
  pop di
  pop si
  pop bx
  sti
  retn
.invalid_letter:
  ; We know DI saves the copy of disk letter
  push di
  push di
  push ds
  push disk_invalid_letter
  call video_printf
  add sp, 8
.die:
  jmp .die

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
  ; ES:DI = 0:0
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
  ; If the current disk num & 0x7F >= DH
  ; then we know we are also in trouble
  mov al, [bp + .CURRENT_DISK_NUMBER]
  and al, 7fh
  cmp dl, al
  jle .error_13h
  ; Save these three to protect them
  push cx
  push dx
  mov ax, disk_param.size
  ; Allocate a system static data chunk
  ; if fail just print error message
  call mem_get_sys_bss
  cmp ax, 0FFFFh
  je .error_unrecoverable
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
  push ds
  push disk_init_found
  call video_printf
  add sp, 14
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
  call video_printf
  add sp, 6
.die:
  jmp die

  ; This function returns the raw byte size of a disk given its
  ; letter number
  ; Size is returned in DX:AX as 512 byte sectors since it may exceeds 
  ; the 16 bit limit
  ; Under the CHS addressing scheme, the maximum possible sector is 24 bit
  ; Set CF if the letter is invalid
  ;   [BP + 4] - Letter
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

  ; This function returns the CHS representation given a linear sector ID
  ; and the drive letter
  ;   [BP + 4] - Device letter
  ;   [BP + 6][BP + 8] - Linear sector ID (LBA) in small endian
  ; Return:
  ;   DH = head
  ;   CH = low 8 bits of cylinder
  ;   CL[6:7] = high 2 bits of cylinder
  ;   CL[0:5] = sector
  ; AX = 0 when success
  ; AX = non-zero when error
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
  ; AX = AH * AL i.e. number of sectors in a track
  mov ah, [bx + disk_param.head]
  inc ah
  mov al, [bx + disk_param.sector] 
  mul ah
  ; AX = sector per cylinder; We know the track ID will fit into 16 bits
  ; there will not be an overflow
  mov cx, ax
  mov ax, [bp + 6]
  mov dx, [bp + 8]
  div cx
  ; Now AX = in-cylinder offset
  ;     DX = cylinder ID
  ; after the exchange
  xchg ax, dx
  mov cl, [bx + disk_param.sector]
  div cl
  ; Now AH = sector offset (starting from 0)
  ;     AL = head ID
  ;     DX = cylinder ID
  inc ah

  ;movzx cx, ah
  ;push cx
  ;movzx cx, al
  ;push cx
  ;push dx
  ;push ds
  ;push .test_string
  ;call video_printf
  ;add sp, 10

  ; Make the high 2 bits of CL the bit 8 and 9 of the cylinder number
  mov cl, dh
  shl cl, 6
  ; CH is the low 8 bits of the cylinder
  mov ch, dl
  ; Make DH the head
  mov dh, al
  ; Make the low 6 bits of CL the sector ID starting from 1
  or cl, ah
  jmp .return
.return_fail:
  xor ax, ax
  inc ax
.return:
  pop bx
  mov sp, bp
  pop bp
  retn
.test_string: db "CHS = %x %y %y", 0ah, 00h

  ; This function returns a pointer to the disk param block
  ; of the given disk letter
  ;   [BP + 4] - The disk letter (low byte)
  ; Returns in AX; Returns NULL if letter is invalid
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
  jmp .return
.return_invalid:
  xor ax, ax
.return:  
  mov sp, bp
  pop bp
  retn

disk_init_error_str: db "Error initializing disk parameters (AX = 0x%x)", 0ah, 00h
disk_init_found:     db "%c: #%y Maximum C/H/S (0x): %x/%y/%y", 0ah, 00h
disk_invalid_letter: db "Invalid disk letter: %c (%y)", 0ah, 00h

; This is an offset in the system segment to the start of the disk param table
; We allocate the table inside the system static data area to save space
; in the compiled object
disk_mapping: dw 0
; Number of elements in the disk mapping table
disk_mapping_num: dw 0