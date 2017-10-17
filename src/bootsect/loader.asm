
;
; loader.asm - The stage I loader
;
; This file provides basic I/O functions. All functions are called
; with CDECL convention, i.e. AX, CX, DX are caller saved, parameters
; are pushed from right to left, and the caller is responsible for clearing
; the stack
;
; char must be extended to 16 bit to be push to the stack
;

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

  ; This function prints a character on the stack to the screen
putchar:

  ; This function copies memory regions that are not overlapped
  ;   [SP + 0] - Dest segment
  ;   [SP + 2] - Dest offset
  ;   [SP + 4] - Source segment
  ;   [SP + 6] - Source offset
  ;   [SP + 8] - Length
memcpy_nonalias:
  push bp
  ; BP points to SP using entrance point as reference
  mov bp, sp
  push ds 
  push si
  push es
  push di
  mov cx, [bp + 12]
  mov si, [bp + 10]
  mov ds, [bp + 8]
  mov di, [bp + 6]
  mov es, [bp + 4]
memcpy_body:  
  ; Whether we have finished copying
  test cx, cx
  je memcpy_ret
  ; Whether there is only 1 byte left
  cmp cx, 1
  je memcpy_last_byte
  mov ax, [ds:si]
  mov [es:di], ax
  sub cx, 2
  add si, 2
  add di, 2
  jmp memcpy_body
memcpy_last_byte:
  ; Copy one byte and return
  mov al, [ds:si]
  mov [es:di], al
memcpy_ret:
  pop di
  pop es
  pop si
  pop ds
  mov sp, bp
  pop bp
  retn

  ; This function sets a chunk of memory as a given byte value
  ;   [SP + 0] - Segment
  ;   [SP + 2] - Offset
  ;   [SP + 4] - Value (should be a zero-extended byte)
  ;   [SP + 6] - Length
memset:
  push bp
  mov bp, sp
  push es
  push di
  
  mov es, [bp + 4]
  mov di, [bp + 6]
  mov al, [bp + 8]
  mov ah, al
  mov cx, [bp + 10]

memset_body:
  test cx, cx
  je memset_ret
  cmp cx, 1
  je memset_last_byte
  mov [es:di], ax  
  sub cx, 2
  add di, 2
  jmp memset_body
memset_last_byte:
  mov [es:di], al
memset_ret:
  pop di
  pop es
  mov sp, bp 
  pop bp
  retn

  ; This function scrolls up by a given number of lines
  ;   [SP + 0] num of lines
video_scroll_up:
  pop cx
  ; If we scroll too much then essentially it is clearing the entire screen
  cmp cx, [video_max_row]
  ja video_scroll_up_clear_all

video_scroll_up_clear_all:
  push es
  push bx
  xor bx, bx
  push word VIDEO_SEG
  pop es
  ; We assume it can be held by a single 16 byte integer
  ; Typically it is just 80 * 25 * 2 = 4000 bytes
  mov ax, [video_max_row]
  mul word [video_max_col]
  pop bx
  pop es
  ret

  ; This moves the video cursor to the next char
video_move_to_next_char:
  mov ax, [video_current_col]
  inc ax
  cmp ax, [video_max_col]
  jne video_inc_col
  ; Clear column to zero and then test row
  mov [video_current_col], 0
  mov ax, [video_current_row]
  inc ax
  cmp ax, [video_max_row]
  jne video_inc_row
  ; We have reached the end of the screen; need to scroll up
  call video_scroll_up
  retn
video_inc_row:
  mov [video_current_row], ax
  retn
video_inc_col:
  mov [video_current_col], ax
  retn

video_current_row: dw 0
video_current_col: dw 0
video_max_row:     dw 25
video_max_col:     dw 80

str_load_success:
  db "Begin stage I", 0

video_offset:
  dw 0000h

