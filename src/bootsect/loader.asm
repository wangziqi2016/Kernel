
section .text
  ; This file is loaded into BX=0200h as the second sector 
	org	0200h
  VIDEO_SEG equ 0b800h
  BUFFER_LEN_PER_LINE equ 80 * 2

  cli
  ; This is the new segment address
  push cs
  push cs
  ; DS and ES are both the same as CS because we can only do segment addressing
  pop ds
  pop es
  ; Reset the stack pointer to 0000:FFF0, i.e. the end of the first segment
  mov sp, 0FFF0h
  sti

  ; Refresh the screen
  mov ax, 0003h
	int 10h

  mov si, str_load_success
  call print_line
  jmp die

die:
  jmp die

  ; This function prints a zero-terminated line whose
  ; length is less than 80; It always starts a new line after printing
print_line:
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

str_load_success:
  db "Begin stage I", 0

video_offset:
  dw 0000h

