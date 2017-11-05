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
  .size:
endstruc

  ; This function detects all floppy and hard disks using BIOS routine
disk_init:
  ; Must disable all interrupts to avoid having non-consecutive disk 
  ; param table in the BSS segment
  cli
  push es
  push di
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
  ; Save these three to protect them
  push cx
  push dx
  mov ax, disk_param.size
  ; Allocate a system static data chunk
  ; if fail just print error message
  call mem_get_sys_bss
  cmp ax, 0FFFFh
  je .error_unrecoverable
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
  pop di
  pop es
  sti
  retn
  ; Just prints what was found
  ; Do not save any register
.print_found:
  mov ax, disk_init_found
  call video_putstr_near
  mov ax, [bp + .CURRENT_DISK_NUMBER]
  push ax
  call video_puthex8
  pop ax
  mov ax, disk_init_chs_str
  mov al, 0ah
  call putchar
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
  mov ax, disk_init_error_str
  call video_putstr_near
.die:
  jmp die

disk_init_error_str: db "Error initializing disk parameters", 0ah, 00h
disk_init_found:     db "Found disk: ", 00h
disk_init_chs_str:       db " C/H/S: ", 00h

; This is an offset in the system segment to the start of the disk param table
; We allocate the table inside the system static data area to save space
; in the compiled object
disk_mapping: dw 0
; Number of elements in the disk mapping table
disk_mapping_num: dw 0