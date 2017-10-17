;
; Boot sector for a floppy disk
;

section .text 
	org	7c00h
	jmp	start

start:
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

  mov si, str1
	call near print_msg

start_load:
  ; leave space to read disk parameters
  sub sp, 001Eh

  mov si, sp
  xor dx, dx
  mov ah, 48h

  int 13h
  jc print_read_sector_error
	jmp die

print_msg:
  push es
  push di
  push word 0b800h
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
	add word [video_offset], 00A0h
	pop di
  pop es
	retn

print_read_sector_error:
  mov si, str2
	call print_msg
	jmp die

die:
  jmp die

str1:
  db "Loading boot sectors... ", 0
str2:
  db "Error reading sectors", 0

  ; We boot from 00h drive which is the 1st floppy
boot_drive:
  db 0h
  ; 18 sectors per track
sector_per_track:
  db 12h
  ; 80 tracks per disk
track_per_disk:
  db 50h
  
  ; Disk parameters used by
current_sector:
  db 01h
current_track:
  db 00h
current_head:
  db 00h

video_offset:
  dw 0

; This line pads the first sector to 512 bytes
  times 510-($-$$) DB 0 
  dw 0AA55H