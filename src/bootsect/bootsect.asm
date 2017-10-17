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

  xor ax, ax
  mov ds, ax
  mov ax, 0b800h
  mov es, ax

  xor di, di
  mov si, str
	
loop_body:
  mov al, [ds:si]
  test al, al
  je after_loop
  mov [es:di], al
	inc si
	inc di
	inc di
  jmp loop_body

after_loop:
	jmp after_loop

str:
  db "Hello World!", 0
  ; This line pads the first sector to 512 bytes
	times 510-($-$$) DB 0 
  dw 0AA55H