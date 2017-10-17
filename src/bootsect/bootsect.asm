;
; Boot sector for a floppy disk
;

section .text 
	org	7C00H
	jmp	start

start:
  ; boot section goes after
	; AH = 00 - set mode; AL = 03h - 80*25@16
	mov ax, 0003h
	int 10h

  ; Set DS=SS; ES=0B800h
  xor ax, ax
  mov ds, ax
	; Set up stack end: 0x0FFF0
	; Note that this sector is on address 0x07C00 - 0x07DFF
	mov ss, ax
	mov sp, 0FFF0h

  mov ax, 0b800h
  mov es, ax

  mov si, str1
	call near print_msg

start_load:
  jmp start_load
  ; leave space to read disk parameters
  sub sp, 001Eh

  mov si, sp
  xor dx, dx
  mov ah, 48h

  int 13h
  jc print_read_param_error

this_line:
  jmp this_line

print_msg:
  push di
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
	mov [video_offset], di
	pop di
	retn

print_read_param_error:
  mov si, str2
	;call 

str1:
  db "Loading boot sectors... ", 0
str2:
  db "Error reading disk parameters", 0
str3:
  db "Error reading sectors", 0

boot_drive:
  db 0
video_offset:
  dw 0

; This line pads the first sector to 512 bytes
  times 510-($-$$) DB 0 
  dw 0AA55H