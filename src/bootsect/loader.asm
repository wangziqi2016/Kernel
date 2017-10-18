
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

  mov si, 400
  mov di, 4
  mov bx, 0775h
test_putchar:
  test si, si
  jnz print_char
  test di, di
  jz after_test_putchar
  mov si, 400
  dec di
  inc bl
print_char:
  mov ax, bx
  call putchar
  dec si
  jmp test_putchar

after_test_putchar:
  call video_move_to_next_line
  call video_clear_all

  push ds
  push str_load_success
  call video_putline
  call video_putline
  call video_putline
  call video_putline
  add sp, 4

die:
  jmp die


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Video functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is video segment address (i.e. 0xB8000 in 20 bit mode)
VIDEO_SEG equ 0b800h
; Number of bytes per row
BUFFER_LEN_PER_LINE equ 80 * 2
; 0x70 is the attr byte - foreground gray; background none
; 0x20 is the space character which we use to represent the cursor
; as a square block 
CURSOR_WORD equ 7020h

  ; This function prints a line on the current cursor position
  ; Note that a new line character is always appended
  ; The line always use default attribute
  ;   [SP + 0] - String offset
  ;   [SP + 2] - String segment
video_putline:
  push bp
  mov bp, sp
  push es
  push bx
  mov bx, [bp + 4]
  mov ax, [bp + 6]
  mov es, ax
.body:
  mov al, [es:bx]
  test al, al
  jz .return
  mov ah, 07h
  call putchar
  inc bx
  jmp .body
.return:
  ; Add a new line
  mov al, 0ah
  call putchar

  pop bx
  pop es
  mov sp, bp
  pop bp
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
.body:  
  ; Whether we have finished copying
  test cx, cx
  je .return
  ; Whether there is only 1 byte left
  cmp cx, 1
  je .last_byte
  mov ax, [ds:si]
  mov [es:di], ax
  sub cx, 2
  add si, 2
  add di, 2
  jmp .body
.last_byte:
  ; Copy one byte and return
  mov al, [ds:si]
  mov [es:di], al
.return:
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

.body:
  test cx, cx
  je .return
  cmp cx, 1
  je .last_byte
  mov [es:di], ax  
  sub cx, 2
  add di, 2
  jmp .body
.last_byte:
  mov [es:di], al
.return:
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
  ; Note that we just modify the video buffer. Current row and col is not 
  ; changed
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
  jae .clear_all

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
.body:
  test cx, cx
  ; If we have finished copying, then just need to clear
  jz .clear_remaining
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
  jmp .body
.clear_remaining:
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
  jmp .return
.clear_all:
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
.return:
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
  jne .inc_col
  ; Clear column to zero and then test row
  mov word [video_current_col], 0
  mov ax, [video_current_row]
  inc ax
  cmp ax, [video_max_row]
  jne .inc_row
  ; We have reached the end of the screen; need to scroll up
  ; Note that current row in the memory stay unchanged
  push word 1
  call video_scroll_up
  add sp, 2
  retn
.inc_row:
  mov [video_current_row], ax
  retn
.inc_col:
  mov [video_current_col], ax
  retn

  ; Moves the display to the next line (i.e. shifting one line above)
  ; Also the column is set to 0
video_move_to_next_line:
  mov word [video_current_col], 0
  mov ax, [video_current_row]
  inc ax
  cmp ax, [video_max_row]
  jnz .inc_row
  push word 1
  call video_scroll_up
  add sp, 2
  retn
.inc_row:
  mov [video_current_row], ax
  retn

  ; This function clears all contents on the screen, and then resets col and row
  ; to zero
video_clear_all:
  mov ax, [video_max_row]
  push ax
  call video_scroll_up
  add sp, 2
  mov word [video_current_col], 0
  mov word [video_current_row], 0
  retn

  ; This function draws the cursor at current location
  ; the cursor is defined as a space character with background
  ; color set to gray (attr = 0x70)
video_putcursor:
  push es
  push bx

  ; Seg video segment, we will use BX later
  mov ax, VIDEO_SEG
  mov es, ax

  mov dx, [video_current_row]
  mov ax, [video_current_col]
  call video_get_offset
  ; BX now points to the word that specifies the character and byte
  mov bx, ax
  mov [es:bx], word CURSOR_WORD

  pop bx
  pop es
  retn

  ; al:ah is the char:attr to put into the stream
  ; Note that we have special processing for \r and \n. In these two cases
  ; the attribute is not used
putchar:
  push bx
  push es
  push si

  ; 0A = new line; 0D = carriage return
  cmp al, 0ah
  je .process_lf
  cmp al, 0dh
  je .process_cr

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
  jmp .return
.process_cr:
  mov word [video_current_col], 0
  jmp .return
.process_lf:
  call video_move_to_next_line
  jmp .return
.return:
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

