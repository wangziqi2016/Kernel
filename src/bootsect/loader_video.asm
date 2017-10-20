_loader_video_start:
;
; loader_video.asm - This file contains character mode video related functions
;

; This is video segment address (i.e. 0xB8000 in 20 bit mode)
VIDEO_SEG equ 0b800h
; Number of bytes per row
BUFFER_LEN_PER_LINE equ 80 * 2
; 0x70 is the attr byte - foreground gray; background none
; 0x20 is the space character which we use to represent the cursor
; as a square block 
CURSOR_WORD equ 7020h

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Printing functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Near wrapper of the far version of putstr; Offset is in AX
  ; This function pushes the current DS
video_putstr_near:
  ; Always assume this is the data segment
  push ds
  push ax
  call video_putstr
  pop ax
  pop ax
  retn

  ; This function prints a line on the current cursor position
  ; Note that there is no newline at the end of the string unless you
  ; add it yourself
  ; The line always use default attribute
  ;   [SP + 0] - String offset
  ;   [SP + 2] - String segment
video_putstr:
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
  mov ah, [video_print_attr]
  call putchar
  inc bx
  jmp .body
.return:
  pop bx
  pop es
  mov sp, bp
  pop bp
  retn

  ; This function prints 16 bit unsigned dec numbers
  ;   [SP + 0] The 16 bit number to print
video_putuint16:
  push bp
  mov bp, sp
  push si
  push di
  mov ax, [bp + 4]
  ; Number of digits we have printed
  xor di, di
.div_body:
  ; DX:AX / 10
  xor dx, dx
  mov cx, 10d
  div cx
  ; Remainder is in DX
  mov si, dx
  mov si, [video_digit_map + si]
  push si
  ; One more digit
  inc di
  test ax, ax
  jnz .div_body
.print_body:
  test di, di
  jz .return
  dec di
  pop ax
  mov ah, [video_print_attr]
  call putchar
  jmp .print_body
.return:
  pop di
  pop si
  mov sp, bp
  pop bp
  retn

  ; A wrapper around _video_puthex()
  ;   [SP + 0] The 16 bit number to print
video_puthex16:
  push bp
  mov bp, sp
  mov ax, [bp + 4]
  ; Push high bytes first (trivial for 16 bit as it is already small endian)
  push ax
  push word 2
  call _video_puthex
  add sp, 4
  mov sp, bp
  pop bp
  retn

  ; Puts 8 bit hex number on screen
  ;   [SP + 0] The 16 bit number to print (low 8 bit)
video_puthex8:
  push bp
  mov bp, sp
  mov ax, [bp + 4]
  ; Push high bytes first (trivial for 16 bit as it is already small endian)
  push ax
  push word 1
  call _video_puthex
  add sp, 4
  mov sp, bp
  pop bp
  retn

  ; This function prints the 16 bit hex value (without leading 0x)
  ; Note that ABCDEF are all in capitcal case
  ;   [SP + 0] - Number of bytes in the hex string
  ;   [SP + 2, 4, ..] - Beginning of the hex string; Small endian
_video_puthex:
  push bp
  mov bp, sp
  push di
  ; Number of loops (bytes)
  mov di, [bp + 4]
.body:
  test di, di
  jz .return  
  dec di
  ; Read the byte into AL
  mov al, [bp + 6 + di]
  mov ah, al
  ; Translate 4 byte
  movzx si, al
  and si, 000fh
  mov al, [video_digit_map + si]
  movzx si, ah
  shr si, 4
  and si, 000fh
  mov ah, [video_digit_map + si]
  ; Need to save it here because AX will be changed
  ; during the func call
  mov si, ax
  mov al, ah
  mov ah, [video_print_attr]
  call putchar
  mov ax, si
  mov ah, [video_print_attr]
  call putchar
  jmp .body
.return:
  pop di
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Video - Update the cursor
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; This moves the video cursor to the next char
  ; This function changes cursor offset
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
  jmp .return
.inc_col:
  mov [video_current_col], ax
  ; Fast path - if we just add column, then the cursor offset can be 
  ; easily modified
  add word [video_cursor_offset], 2
  retn
.inc_row:
  mov [video_current_row], ax
.return:
  ; Compute the new offset
  call video_update_cursor_offset
  retn

  ; Moves the display to the next line (i.e. shifting one line above)
  ; Also the column is set to 0
  ; This function changes cursor offset
video_move_to_next_line:
  mov word [video_current_col], 0
  mov ax, [video_current_row]
  inc ax
  cmp ax, [video_max_row]
  jnz .inc_row
  push word 1
  call video_scroll_up
  add sp, 2
  jmp .return
.inc_row:
  mov [video_current_row], ax
.return:
  call video_update_cursor_offset
  retn

  ; This function just moves the cursor to the current line
  ; The effect is like printing a CR character
  ; This function updates the cursor offset
video_move_to_this_line:
  mov [video_current_col], word 0
  call video_update_cursor_offset
  retn

  ; This function clears all contents on the screen, and then resets 
  ; col and row to zero
video_clear_all:
  mov ax, [video_max_row]
  push ax
  call video_scroll_up
  add sp, 2
  mov word [video_current_col], 0
  mov word [video_current_row], 0
  mov word [video_cursor_offset], 0
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
  ; BX now points to the word that specifies the character and byte
  mov bx, [video_cursor_offset]
  ; Save the content underneath first
  mov ax, [es:bx]
  mov [video_cursor_saved], ax
  ; Then write the actual cursor character
  mov [es:bx], word CURSOR_WORD
  pop bx
  pop es
  retn
  
  ; This function clears the cursor
video_clearcursor:
  push es
  push bx
  ; Seg video segment, we will use BX later
  mov ax, VIDEO_SEG
  mov es, ax
  ; BX now points to the word that specifies the character and byte
  mov bx, [video_cursor_offset]
  ; Use the saved value
  mov ax, [video_cursor_saved]
  mov [es:bx], ax
  pop bx
  pop es
  retn

  ; This function updates the cursor offset
video_update_cursor_offset:
  mov dx, [video_current_row]
  mov ax, [video_current_col]
  call video_get_offset
  mov [video_cursor_offset], ax
  retn

  ; al:ah is the char:attr to put into the stream
  ; Note that we have special processing for \r and \n. In these two cases
  ; the attribute is not used
putchar:
  push bx
  push es
  push si
  
  ; Protect AX before calling function
  mov si, ax
  call video_clearcursor
  mov ax, si

  ; 0A = new line; 0D = carriage return
  cmp al, 0ah
  je .process_lf
  cmp al, 0dh
  je .process_cr

  ; BX is the offset to write character
  mov bx, [video_cursor_offset]
  mov ax, VIDEO_SEG
  mov es, ax
  mov [es:bx], si

  ; Go to next char's position
  call video_move_to_next_char
  jmp .return
.process_cr:
  call video_move_to_this_line
  jmp .return
.process_lf:
  call video_move_to_next_line
.return:
  ; Restore the cursor here before return
  call video_putcursor

  pop si
  pop es
  pop bx
  retn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Low-level interrupt & hardware mode switching
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ; Initialize the video card to a mode under which this module
  ; is capable to work
video_init:
  ; AH = 00H - switch mode
  ; AL = 03H - 80*25@16 VGA with B800:0000
  mov ax, 0003h
  int 10h
  ; AH = 01h - Set cursor shape
  mov ah, 01h
  ; CX = 2000h - Hide the cursor
  mov cx, 2000h
  int 10h
  retn

video_current_row:    dw 0
video_current_col:    dw 0
; The offset of the cursor on the video memory
; Note that this value is not represented in row-col form, because
; the cursor position is usually a by-product of other computations
; or easily obtained
video_cursor_offset:  dw 0
; This is the saved value under the location of the cursor
; We save it here when we draw the cursor, and restore it when
; we undraw the cursor
video_cursor_saved:   dw 0
; These two should be used as constants
video_max_row:        dw 25
video_max_col:        dw 80

; This is the attribute we use while printing
; Note that putchar() does not directly read this
; The caller of putchar is responsible
video_print_attr:     db 07h
; This maps from value to digit ASCIIs
video_digit_map:      db "0123456789ABCDEF"

str_load_success:
  db "Begin stage I", 0DH, 0Ah, 00
