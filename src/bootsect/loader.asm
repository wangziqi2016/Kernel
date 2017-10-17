
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

  mov si, 400
  mov di, 4
  mov bx, 0775h
test_putchar:
  test si, si
  jnz print_char
  test di, di
  jz die
  mov si, 400
  dec di
  inc bl
print_char:
  mov ax, bx
  call putchar
  dec si
  jmp test_putchar

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

  ; This function copies memory regions that are not overlapped
  ;   [SP + 0] - Dest offset
  ;   [SP + 2] - Dest segment
  ;   [SP + 4] - Source offset
  ;   [SP + 6] - Source segment
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
  mov si, [bp + 8]
  mov ds, [bp + 10]
  mov di, [bp + 4]
  mov es, [bp + 6]
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
  ;   [SP + 0] - Offset
  ;   [SP + 2] - Segment
  ;   [SP + 4] - Value (should be a zero-extended byte)
  ;   [SP + 6] - Length
memset:
  push bp
  mov bp, sp
  push es
  push di
  
  mov di, [bp + 4]
  mov es, [bp + 6]
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

  ; This function computes the offset of a given position
  ; Note that we do not check for the correctness of the row
  ;   DX:AX = Row ID:Col ID
  ;   Returns in AX as a byte offset
video_get_offset:
  xchg dx, ax
  ; DX:CX is col ID:row ID now
  mov cx, dx
  ; Return (row * max_col + col) * 2
  mul word [video_max_col]
  add ax, cx
  shl ax, 1
  retn

  ; This function scrolls up by a given number of lines
  ;   [SP + 0] num of lines
video_scroll_up:
  push bp
  mov bp, sp
  push si
  push di
  push bx

  ; Number of lines to scroll up
  mov ax, [bp + 4]
  ; If we scroll too much then essentially it is clearing the entire screen
  cmp ax, [video_max_row]
  jae video_scroll_up_clear_all

  ; DX:AX = row:col for computing offset
  mov dx, ax
  xor ax, ax
  call video_get_offset
  ; SI is the source offset which is the row that will become the first row
  mov si, ax
  ; DI is dest offset which is 0
  xor di, di
  ; BX is the number of bytes per line
  ; We know that BX will not be modified by subroutines
  mov bx, [video_max_col]
  shl bx, 1

  ; CX is numer of iterations we need to perform
  ; in order to move the entire screen up
  mov cx, [video_max_row]
  sub cx, [bp + 4]
video_scroll_up_body:
  test cx, cx
  ; If we have finished copying, then just need to clear
  jz video_scroll_up_clear_remaining
  ; Save register
  push cx
  ; Length
  push bx
  ; Source and dest address
  push word VIDEO_SEG
  push si
  push word VIDEO_SEG
  push di
  call memcpy_nonalias
  add sp, 10

  ; Restore register
  pop cx
  dec cx
  add si, bx
  add di, bx
  jmp video_scroll_up_body
video_scroll_up_clear_remaining:
  ; Number of lines to clear (parameter)
  mov ax, [bp + 4]
  ; Compute the number of bytes to clear
  mul word [video_max_col]
  shl ax, 1
  ; SI from the previous loop is the starting address
  ; of the region we are going to clear
  push ax
  push word 0
  push VIDEO_SEG
  ; Note that the destination now points exactly to the lines we
  ; want to clear
  push di
  call memset
  add sp, 8
  jmp video_scroll_up_ret
video_scroll_up_clear_all:
  ; We assume it can be held by a single 16 byte integer
  ; Typically it is just 80 * 25 * 2 = 4000 bytes
  mov ax, [video_max_row]
  mul word [video_max_col]
  ; Do not forget to multiply this by 2
  shl ax, 1
  ; memset - Length
  push ax
  ; memset - Value
  push word 0
  ; memset - Segment
  push VIDEO_SEG
  ; memset - Offset
  push word 0
  call memset
  add sp, 8
video_scroll_up_ret:
  pop bx
  pop di
  pop si
  mov sp, bp
  pop bp
  retn

  ; This moves the video cursor to the next char
video_move_to_next_char:
  mov ax, [video_current_col]
  inc ax
  cmp ax, [video_max_col]
  jne video_inc_col
  ; Clear column to zero and then test row
  mov word [video_current_col], 0
  mov ax, [video_current_row]
  inc ax
  cmp ax, [video_max_row]
  jne video_inc_row
  ; We have reached the end of the screen; need to scroll up
  ; Note that current row in the memory stay unchanged
  push word 1
  call video_scroll_up
  add sp, 2
  retn
video_inc_row:
  mov [video_current_row], ax
  retn
video_inc_col:
  mov [video_current_col], ax
  retn

  ; al:ah is the char:attr to put into the stream
putchar:
  push bx 
  push es
  push si

  mov si, ax
  mov dx, [video_current_row]
  mov ax, [video_current_col]
  call video_get_offset
  ; AX is the offset
  mov bx, ax
  mov ax, VIDEO_SEG
  mov es, ax
  mov [es:bx], si

  ; Go to next char's position
  call video_move_to_next_char

  pop si
  pop es
  pop bx
  retn

video_current_row: dw 0
video_current_col: dw 0
video_max_row:     dw 25
video_max_col:     dw 80

str_load_success:
  db "Begin stage I", 0

video_offset:
  dw 0000h

