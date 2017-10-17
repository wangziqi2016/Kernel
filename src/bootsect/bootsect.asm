;
; Boot sector for a floppy disk
;

section .text 
	org	7c00h
  
  ; Video buffer
  VIDEO_SEG equ 0b800h
  ; 80 * 2 = 160 char + attr per line
  BUFFER_LEN_PER_LINE equ 00a0h
  ; We start loading the sector at 0x10000, i.e. the second
  ; 64 KB segment. The boot sector is in the first 64 KB
  LOAD_SEG equ 1000h
  ; Each sector is 512 byte
  SECTOR_SIZE equ 0200h

	jmp	start

start:
  ; Clear interrupt before we set up the stack
  cli
	; AH = 00 - set mode; AL = 03h - 80*25@16
	mov ax, 0003h
	int 10h

  ; Set DS=SS; ES undefined
  xor ax, ax
  mov ds, ax
	; Set up stack end: 0x0FFF0
	; Note that this sector is on address 0x07C00 - 0x07DFF
	mov ss, ax
	mov sp, 0FFF0h
  sti

  mov si, str1
	call print_msg

start_load:
  ; ES points to 0x10000 segment
  push word LOAD_SEG
  ; Read into 1000:0000
  pop es
  xor bx, bx
  mov cx, [num_sector_to_read]
read_next_sector:
  ; This is the number of sectors we read from 
  ; the 1st sector
  call read_sector
  call next_sector

  ; This means we have seen an overflow as we always read 512 bytes
  cmp bx, 0000h
  jnz test_num_sector
  ; Clear BX as the offset
  xor bx, bx
  ; Add 0x1000 to ES, which means we switch to the next 64KB segment
  mov ax, es
  add ax, 1000h
  mov es, ax
test_num_sector:
  dec cx
  jnz read_next_sector

  ; Verify the content after reading
  push word LOAD_SEG
  pop es
  ; bx has been changed to the new offset
  mov ax, [es:SECTOR_SIZE - 2]
  cmp ax, 0aa55h
  jne print_verify_sector_error

  ; Jump to the code we just loaded
  ; Note: Segment is on high address
  push word LOAD_SEG
	push word SECTOR_SIZE
  retf
  
  ; This function reads a sector into ES:BX
  ; using the parameter at the end of this file
  ; It will change BX to the next sector
  ;  - Changes AX and DX
read_sector:
  push bx
  push cx
  ; Retry remains
  push word 3

read_sector_retry:
  mov ax, 0201h
  ; DL = drive ID. DH = disk head
  mov dx, [boot_drive]
  ; Note that bit 6 and 7 in CL are actually bit
  ; 8 and 9 of the track. We just assume they are 
  ; always 0 (only 80 tracks)
  mov cx, [current_sector]
  int 13h
  jc read_sector_reset
  ; AL contains the actual # of tracks read
  ; AH contatns the return code (00 = normal)
  cmp ax, 0001h
  jne read_sector_reset

  ; Return here normally
  pop cx
  pop cx
  pop bx
  add bx, SECTOR_SIZE
  retn

read_sector_reset:
  ; Check whether we have run out of retries
  pop cx
  test cx, cx
  je print_read_sector_error
  ; AH = 00H to reset the device speficied by DL
  mov ah, 00h
  mov dl, [boot_drive]
  int 13h
  jc print_read_sector_error
  ; Decrease this number and continue execution
  dec cx
  push cx
  jmp read_sector_retry

  ; This function changes the parameters of the disk
  ;   - Changes AX
  ;
  ; We do as the following:
  ; (1) Check whether we have reached the maximum sector (inclusive)
  ;     If not then just increment the sector
  ; (2) Otherwise, reset sector to 1, and check whether we have reached the
  ;     maximum head. If not just incremant the head
  ; (3) Otherwise, reset head to 0, and check whether we have reached the 
  ;     maximum track. If not just increment the track
  ; (4) Otherwise, report error, because we have reached the end of the disk
next_sector:
  mov al, [current_sector]
  ; Whether we have reached the end of a track
  cmp al, [sector_per_track]
  jb inc_sector
  
  ; Reset sector (always start at 1)
  mov byte [current_sector], 01h
  ; Then check head
  mov al, [current_head]
  inc al
  cmp al, [head_per_disk]
  jne inc_head
  ; Reset head
  mov byte [current_head], 00h
  mov al, [current_track]
  inc al
  cmp al, [track_per_disk]
  jne inc_track
  jmp print_reach_disk_end_error

inc_track:
  inc byte [current_track]
  retn
inc_head:
  inc byte [current_head]
  retn
inc_sector:
  inc byte [current_sector]
  retn

  ; This function prints a zero-terminated line whose
  ; length is less than 80; It always starts a new line after printing
print_msg:
  push es
  push di
  ; Reload ES as the video buffer segment
  push word VIDEO_SEG
  pop es
  mov di, [video_offset]
print_msg_body:
  mov al, [ds:si]
  test al, al
  je print_msg_ret
  mov [es:di], al
  inc si
  inc di
  inc di
  jmp print_msg_body
print_msg_ret:
  ; Go to the next line
	add word [video_offset], BUFFER_LEN_PER_LINE
	pop di
  pop es
	retn

print_reach_disk_end_error:
  mov si, str4
  call print_msg
  jmp die

print_read_sector_error:
  mov si, str2
	call print_msg
	jmp die

print_verify_sector_error:
  mov si, str3
  call print_msg
  jmp die

die:
  jmp die

str1:
  db "Loading boot sectors...", 0
str2:
  db "Error reading sectors", 0
str3:
  db "Error verifying sectors", 0
str4:
  db "Reached the end of disk", 0

  ; 18 sectors per track
sector_per_track:
  db 12h
  ; 80 tracks per disk
track_per_disk:
  db 50h
head_per_disk:
  db 02h
  ; Maximum is 2879 (2880 - 1)
num_sector_to_read:
  dw 10d
  
  ; CL + CH = sector + track
current_sector:
  db 01h
current_track:
  db 00h
  ; DL + DH = drive ID + disk head
boot_drive:
  db 0h
current_head:
  db 00h

video_offset:
  dw 0

; This line pads the first sector to 512 bytes
  times 510-($-$$) DB 0 
  dw 0AA55H