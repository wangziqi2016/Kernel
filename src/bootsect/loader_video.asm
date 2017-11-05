_loader_video_start:
;
; loader_video.asm - This file contains character mode video related functions
;
; 1. All routines in this file do not assume ES. This implies that ES must
;    be saved and loaded with the video seg address. Also, ISR could safely
;    call routines in this file without loading ES
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

  ; This function is a modified/simplified version of printf
  ; Interface: void printf(const char *fmt, ...);
  ; Format string specification:
  ;   - %d 16 bit signed integer
  ;   - %u 16 bit unsigned integer
  ;   - %x 16 bit hex (always upper case, like traditional %X)
  ;   - %y 8  bit hex (always upper case); Need to push it as 16 bit
  ;   - %c a character; Need to push it as 16 bit
  ;   - %s a near string, using the system segment
  ;   - %S a far string, using the provided offset:segment notation
  ;   - %% The percent sign itself
  ; As the normal printf() implementation, the caller should clear the 
  ; stack, and parameters are pushed from right to left, all 16 bit aligned
  ;   [BP + 4] - The format string offset
  ;   [BP + 6] - The format string segment
  ; We keep the following invariant:
  ;   [ES:DI] always points to the next character to print before the main loop
  ;   [SS:BP + SI] always points to the 16 bit aligned next parameter
video_printf:
  push bp
  mov bp, sp
  push es
  push bx
  push si
  push di
  ; Set ES:DI to point to the format string
  mov ax, [bp + 6]
  mov es, ax
  mov di, [bp + 4]
  ; Set SI to be the relative distance from SS:BP to the next argument
  mov si, 8
.body:
  ; If the next char is NUL then just return
  mov al, [es:di]
  inc di
  test al, al
  je .return
  cmp al, '%'
  je .process_format
  mov ah, [video_print_attr]
  call putchar
  jmp .body
.process_format:
  ; Get the char after percent sign, if it is NUL then just print percent and
  ; done
  mov al, [es:di]
  inc di
  test al, al
  je .last_char_is_percent
  ; %d - 16 bit integer
  cmp al, 'u'
  je .process_percent_u
  ; If there is an unknown percent specifier, we just print these two out
  jmp .unknown_percent
  ; For unknown percent, just print a percent character and the char after it
.process_percent_u:
  mov ax, [bp + si]
  add si, 2
  push ax
  push video_putuint16
  pop ax
  jmp .body
.unknown_percent:
  mov al, '%'
  mov ah, [video_print_attr]
  call putchar
  mov al, [es:di - 1]
  mov ah, [video_print_attr]
  call putchar
  jmp .body
.last_char_is_percent:
  mov al, '%'
  mov ah, [video_print_attr]
  call putchar
.return:
  pop di
  pop si 
  pop bx
  pop es
  mov sp, bp
  pop bp
  retn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Video - Manage the buffer
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

  ; This moves the video cursor to the previous char
  ; Specification is the same as video_move_to_next_char() except that
  ; it moves backward, and that it stops when both row and col are 0x00
  ; Note that this function is simpler, as there are only two cases:
  ;   1. Offset -= 2
  ;   2. Offset not change
video_move_to_prev_char:
  mov ax, [video_current_col]
  test ax, ax
  jnz .dec_col
  mov ax, [video_current_row]
  ; If column is 0 and row is 0, we just return
  ; This is different from next char case where we 
  ; just shift lines
  test ax, ax
  je .already_left_top
  ; Current row -= 1
  dec ax
  mov [video_current_row], ax
  ; Current col = max col - 1
  mov ax, [video_max_col]
  dec ax
  mov [video_current_col], ax
  jmp .return
.dec_col:
  dec ax
  mov [video_current_col], ax
.return:
  sub word [video_cursor_offset], 2
.already_left_top:
  retn

  ; This moves the video cursor to the next char
  ; This function changes cursor offset, but does not draw
  ; or clear the cursor (caller should handle this)
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
  ; Return here without recalculating the offset
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
video_move_to_line_head:
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
  ;mov [es:bx], word CURSOR_WORD
  mov [es:bx + 1], byte 70h
  pop bx
  pop es
  retn
  
  ; This function clears the cursor
  ; This function is idempotent
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

  ; This function updates the cursor offset to be consistent
  ; with the current row and col
video_update_cursor_offset:
  mov dx, [video_current_row]
  mov ax, [video_current_col]
  call video_get_offset
  mov [video_cursor_offset], ax
  retn

  ; Put AX into the current location without moving the cursor
  ;     CX is either 0, or the offset to the current location
  ; Note that the caller must guarantee the target address is within
  ; the bound. This function does not provide bound check, and also 
  ; does not scroll up the screen
  ;
  ; Note that this function does not clear cursor. The caller should
  ; clear cursor first
video_raw_put:
  push bx
  push es
  push word VIDEO_SEG
  pop es
  shl cx, 1
  add cx, [video_cursor_offset]
  mov bx, cx
  mov [es:bx], ax
  pop es
  pop bx
  retn

  ; This function moves the cursor forward or backward depending on the arument
  ; This function handles screen scrolling up
  ; Note that this function does not clear and redraw the cursor
  ;   [SP + 0] - Amount. If positive then forward; otherwise backward
video_move_cursor:
  push bp
  mov bp, sp
  push si
  mov si, [bp + 4]
  ; Compare SI with 0 using signed comparison
  xor ax, ax
  cmp si, ax
  je .return
  jl .move_back
.move_forward_body:
  test si, si
  jz .return
  dec si
  call video_move_to_next_char
  jmp .move_forward_body
.move_back:
  neg si
.move_back_body:
  test si, si
  je .return
  dec si
  call video_move_to_prev_char
  jmp .move_back_body
.return:
  pop si
  mov sp, bp
  pop bp
  retn

  ; al:ah is the char:attr to put into the stream
  ; Note that we have special processing for the following characters: 
  ;   1. \r - Jump to the head of the line 
  ;   2. \n - Jump to next line. Scroll lines up if necessary
  ;   3. 0x0E - Jump to previous char and clear the location
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
  cmp al, KBD_KEY_BKSP
  je .process_bksp
  ; Before entering here, SI must contain the character we want to draw
.print_ax:
  mov dx, ax
  ; BX is the offset to write character
  mov bx, [video_cursor_offset]
  mov ax, VIDEO_SEG
  mov es, ax
  mov ax, dx
  mov [es:bx], ax
  mov ax, si
  ; For bksp we do not go forward
  cmp al, KBD_KEY_BKSP
  je .return
  ; Otherwise go to next char's position
  call video_move_to_next_char
  jmp .return
.process_bksp:
  call video_move_to_prev_char
  ; SI = 0x0700 to print normal attr with null
  mov ax, 0700h
  jmp .print_ax
.process_cr:
  call video_move_to_line_head
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
