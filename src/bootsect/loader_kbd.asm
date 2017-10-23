_loader_kbd_start:
;
; loader_kbd.asm - This file implements the keyboard driver
;

KBD_BUFFER_CAPACITY equ 64
; The following defines the status word
KBD_CTRL_ON         equ 01h
KBD_SHIFT_ON        equ 02h
KBD_ALT_ON          equ 04h
KBD_CAPS_LOCK       equ 08h
KBD_NUM_LOCK        equ 10h
; This flag will be cleared if it is present when an interrupt happens
; The correspinding scan code in the buffer, however, will have it set
KBD_EXTENDED_ON     equ 20h
; This is not set by the ISR, but when we try to convert a scan code 
; to a char, and the scan code is not a char, we just set this flag in
; the status byte (i.e. AH)
KBD_UNPRINTABLE     equ 40h

; Whether a key is down or up. AND with this and if NE then 
; we know it is up - NOTE it is a mask NOT a scancode
KBD_KEY_UP          equ 80h
; This is the scan code for backspace key
KBD_KEY_BKSP        equ 0eh

KBD_EXTENDED_ARROW_LEFT  equ 4bh
KBD_EXTENDED_ARROW_RIGHT equ 4dh
KBD_EXTENDED_ARROW_UP    equ 48h
KBD_EXTENDED_ARROW_DOWN  equ 50h

  ; This function intializes the keyboard interrupt
kbd_init:
  push es
  push bx
  cli
  ; Make ES ponits to the first segment
  push word 0
  pop es
  ; This is the offset of INT 9h
  mov bx, 9h * 4
  mov ax, cs
  ; Install the offset on lower address and CS segment on higher address
  mov [es:bx + 2], ax
  mov word [es:bx], kbd_isr

  sti
  pop bx
  pop es
  retn
  
  ; This is the keyboard interrupt handler
  ; We pre-process the scan code in the following manner:
  ;   1. Bytes following 224h is extended key. We will save their scan code
  ;      with extended bit.
  ;   2. If the lower 7 bits are shift, ctrl, alt then we update the status 
  ;      word
  ;   3. Otherwise we ignore the scan code with bit 7 set (UP key)
  ;   4. For ordinary keys, we add the scan code of the key in lower 
  ;      byte, and the status word in higher byte
  ; Note that for (1), we cannot do it in one call, because they are sent via 2
  ; interupts. We just set the extended flag, and clear it after we have 
  ; received the second byte in a later interrupt
kbd_isr:
  pusha
  push ds
  push es
  ; Read from port 0x60
  in al, 60h
  ; Next we process the key and update the current status
  ; E0H = extended key
  cmp al, 0e0h
  je .process_extended_flag
  ; LEFT SHIFT
  cmp al, 2ah
  je .process_shift_down
  ; RIGHT SHIFT
  cmp al, 36h
  je .process_shift_down
  cmp al, 0aah
  je .process_shift_up
  cmp al, 0b6h
  je .process_shift_up
  ; Left ctrl
  cmp al, 1dh
  je .process_ctrl_down
  cmp al, 9dh
  je .process_ctrl_up
  ; Left ALT
  cmp al, 38h
  je .process_alt_down
  cmp al, 0b8h
  je .process_alt_up
  ; CAPS LOCK; Note that for this we just toggle its bit using XOR
  ; Also we ignore the UP of this key
  cmp al, 3ah
  je .process_caps_lock
  ; CAPS LOCK UP
  cmp al, 0bah
  je .finish_interrupt
  ; NUM LOCK DOWN
  cmp al, 45h
  je .process_num_lock
  ; NUM LOCK UP
  cmp al, 0c5h
  je .finish_interrupt
  test al, KBD_KEY_UP
  je .process_other_down
  jmp .process_other_up
.process_extended_flag:
  or byte [kbd_status], KBD_EXTENDED_ON
  ; Note that since we set the flag on in this interupr,
  ; we just clear it in the next interrupt, so we should skip
  ; the part that clears the EXTENDED flag
  jmp .finish_interrrupt_with_extend_flag
.process_shift_down:
  or byte [kbd_status], KBD_SHIFT_ON
  jmp .finish_interrupt
.process_shift_up:
  ; Mask off the shift bit
  and byte [kbd_status], ~KBD_SHIFT_ON
  jmp .finish_interrupt
.process_ctrl_down:
  or byte [kbd_status], KBD_CTRL_ON
  jmp .finish_interrupt
.process_ctrl_up:
  and byte [kbd_status], ~KBD_CTRL_ON
  jmp .finish_interrupt
.process_alt_down:
  or byte [kbd_status], KBD_ALT_ON
  jmp .finish_interrupt
.process_alt_up:
  and byte [kbd_status], ~KBD_ALT_ON
  jmp .finish_interrupt
.process_caps_lock:
  xor byte [kbd_status], KBD_CAPS_LOCK
  jmp .finish_interrupt
.process_num_lock:
  xor byte [kbd_status], KBD_NUM_LOCK
  jmp .finish_interrupt
.process_other_down:
  ; Use DX to hold the value
  mov dx, ax
  mov ax, [kbd_scan_code_buffer_size]
  cmp ax, KBD_BUFFER_CAPACITY
  je .full_buffer
  inc ax
  mov [kbd_scan_code_buffer_size], ax
  ; If head cannot be written into, we wrap back to index = 0
  ; Otherwise just use head
  mov ax, [kbd_scan_code_head]
  cmp ax, KBD_BUFFER_CAPACITY
  jne .put_buffer
  xor ax, ax
.put_buffer:
  ; Compute the target address in the buffer in BX
  ;   BX = base + index * 2
  ; because each entry is 2 byte
  mov bx, kbd_scan_code_buffer
  shl ax, 1
  add bx, ax
  ; Move the head to the next location and store it back
  shr ax, 1
  inc ax
  mov [kbd_scan_code_head], ax
  ; Restore AX saved in DX
  mov ax, dx
  ; We know DL is the scan code unchanged, and CL is the 
  ; old status bit
  ; BX is the address to write
  ; Read the most up-to-date status into DH
  mov ah, [kbd_status]
  mov [bx], ax
  ; Just return
.process_other_up:
.finish_interrupt:
  ; Mask off the extended key bit
  and byte [kbd_status], ~KBD_EXTENDED_ON
.finish_interrrupt_with_extend_flag:
  ; Reset keyboard by reading and writing into 0x61h
  in al, 61h
  or al, 80h
  out 61h, al
  in al, 61h
  and al, 7fh
  out 61h, al
  ; Send EOI to the PIC
  mov al, 20h
  out 20h, al
  jmp .return
.full_buffer:
  ; Clear the buffer when it overflows
  mov word [kbd_scan_code_head], 0
  mov word [kbd_scan_code_tail], 0
  mov word [kbd_scan_code_buffer_size], 0
  mov byte [kbd_status], 0
.return:
  pop es
  pop ds
  ; Note that SP is ignored
  popa
  iret
  
  ; This function is non-blocking
  ; It returns a scan code from the buffer in AL; If the buffer is empty it 
  ; returns 0 in AX. AH is the status bit when the key is pushed down
  ; This function is non-blocking
kbd_getscancode:
  ; Must ensure atomicity of this operation
  cli
  push bx
  mov ax, [kbd_scan_code_buffer_size]
  test ax, ax
  ; Note that when we do this jump, AX is already zero
  je .return
  dec ax
  mov [kbd_scan_code_buffer_size], ax
  mov ax, [kbd_scan_code_tail]
  ; If the tail points to an unreadable location
  ; we just wrap back and perform the read
  cmp ax, KBD_BUFFER_CAPACITY
  jne .fetch_code
  xor ax, ax
.fetch_code:
  ; BX = base + AX * 2
  mov bx, kbd_scan_code_buffer
  shl ax, 1
  add bx, ax
  ; Increment and write back the index first
  shr ax, 1
  inc ax
  mov [kbd_scan_code_tail], ax
  ; Read the scan code
  mov ax, word [bx]
.return:
  pop bx
  sti
  retn

  ; Flush the keyboard buffer
  ; This function is always executed atomically
kbd_flush:
  cli
  mov word [kbd_scan_code_head], 0
  mov word [kbd_scan_code_tail], 0
  mov word [kbd_scan_code_buffer_size], 0
  mov byte [kbd_status], 0
  sti
  retn

  ; This function converts a AH:AL scan code and its status byte
  ; to a printable character. AH is not affected.
  ; If the scan code does not represent a printable char, then we set
  ; KBD_UNPRINTABLE bit in the status byte (i.e. AH)
kbd_tochar:
  push bx
  ; Do not support extended keys and control sequence
  test ah, KBD_EXTENDED_ON
  jne .return_not_a_char
  test ah, KBD_CTRL_ON
  jne .return_not_a_char
  ; If shift is on we use the other table
  test ah, KBD_SHIFT_ON
  jne .use_shift_table
  mov bx, kbd_unshifted_scan_code_map
  jmp .translate
.use_shift_table:
  mov bx, kbd_shifted_scan_code_map
  ; Before entering this part, BX must hold the address of the table
.translate:
  movzx dx, al
  add bx, dx
  mov bl, byte [bx]
  test bl, bl
  je .return_not_a_char
  mov al, bl
  ; Check whether caps lock for letters is on; If not just
  ; return. Otherwise, we check first whether it is [a, z],
  ; and if it is, we then convert it to capital
  test ah, KBD_CAPS_LOCK
  je .return
  ; Then test whether it is a character
  cmp al, 'a'
  jb .return
  cmp al, 'z'
  ja .return
  and al, 0DFh
.return:
  pop bx
  retn
  ; This branch sets the unprintable flag and return
.return_not_a_char:
  or ah, KBD_UNPRINTABLE
  jmp .return

  ; This function blocks on the keyboard and receives printable characters.
  ; The received characters are put into a given buffer, until ENTER or
  ; CTRL+C is pressed. The former ends this process, and returns with status 
  ; flag indicating that the function returns normally. Otherwise, we return
  ; status indicating that the process was interrupted
  ; If the number of characters exceeds the given length, then we stop
  ; putting anything into the buffer, but the function does not return.
  ;
  ; Note:
  ;   (1) This function does not append '\n' at the end. But it appends '\0'
  ;       and the buffer should be long enough to hold the '\0'
  ;   (2) Returns 0 if exited normally; Otherwise interrupted (CTRL+C)
  ;   (3) TAB is ignored; SPACE works as always
  ;   (4) You can use BACKSPACE to go back one character (until the buffer is 
  ;       empty). You can also use LEFT and RIGHT arrow keys to move between
  ;       characters. Existing characters will be shifted if you type.
  ;   (5) CTRL+C Interrupts the process and this function returns 0xFFFF
  ;       Otherwise it returns the actual number of bytes
  ;   [SP + 0] Whether to echo back; 0 means echo, 1 means not
  ;   [SP + 2] Length of the buffer (also the max. character count, 
  ;            including '\0')
  ;   [SP + 4] Offset of the buffer
  ;   [SP + 6] Segment of the buffer
kbd_getinput:
  push bp
  mov bp, sp
  push es
  push bx
  push si
  push di
  ; Load ES with the target buffer segment
  mov ax, [bp + 10]
  mov es, ax
  ; ES:BX is the offset of the buffer. It always points to the next
  ; character location
  mov bx, [bp + 8]
  ; SI is the address also, but it denotes the current cursor position
  mov si, bx
.next_scancode:
  call kbd_getscancode
  test ax, ax
  je .next_scancode
  ; If CTRL is on then process CTRL
  test ah, KBD_CTRL_ON
  jne .process_ctrl
  test ah, KBD_EXTENDED_ON
  jne .process_extended
  ; If it is ENTER we simply return
  cmp al, 1ch
  je .normal_return
  ; If it is backspace we need to move back
  cmp al, KBD_KEY_BKSP
  je .process_bksp
  ; Translate the scan code to a printable character
  call kbd_tochar
  ; Ignore unprintable characters, including TAB
  test ah, KBD_UNPRINTABLE
  jne .next_scancode
  ; Compute the length of (the current string + 1) and the 
  ; the buffer length. If they equal just ignore everything
  mov dx, bx
  sub dx, [bp + 8]
  inc dx
  cmp dx, [bp + 6]
  je .next_scancode
  ; If the cursor is currently not at the end of the input, we need to shift
  ; the memory buffer right, and then refresh the latter part
  cmp si, bx
  jne .shift_right
  ; Otherwise, put the char into the buffer and move the pointer
  mov [es:bx], al
  inc bx
  ; Also need to change the cursor position
  inc si
  ; Then test echo back flag before printing it (if non-zero then do not print)
  mov dx, [bp + 4]
  test dx, dx
  jne .next_scancode
  mov ah, [video_print_attr]
  call putchar
  jmp .next_scancode
.process_bksp:
  ; If we are already at the beginning of the buffer just ignore this
  cmp bx, [bp + 8]
  je .next_scancode
  dec bx
  dec si
  ; Print BKSP character
  mov al, KBD_KEY_BKSP
  call putchar
  jmp .next_scancode
.process_extended:
  cmp al, KBD_EXTENDED_ARROW_LEFT
  je .process_left_arrow
  cmp al, KBD_EXTENDED_ARROW_RIGHT
  je .process_right_arrow
  jmp .next_scancode
.process_left_arrow:
  ; If we are already at the beginning of the line, then ignore
  cmp si, [bp + 8]
  je .next_scancode
  call video_clearcursor
  call video_move_to_prev_char
  call video_putcursor
  ; Also decrement SI to reflect the fact
  dec si
  jmp .next_scancode
.process_right_arrow:
  ; If we are already on the last location then ignore it
  cmp si, bx
  je .next_scancode
  call video_clearcursor
  call video_move_to_next_char
  call video_putcursor
  inc si
  jmp .next_scancode
.process_ctrl:
  ; CTRL + C (note that this is raw scan code)
  cmp al, 2eh
  je .ctrl_c_return
  ; By default just ignore it
  jmp .next_scancode
.ctrl_c_return:
  ; Set AX = 0xFFFF
  xor ax, ax
  dec ax
  jmp .return
  ; Before entering this, AL contains the scan code
.shift_right:
  ; DX = the # of chars need to shift
  mov dx, bx
  sub dx, si
  ; Protect AX
  mov di, ax
  ; Amount, length, segment and offset
  push word 1
  push dx
  push es
  push si
  call memshift_tohigh
  add sp, 8
  ; AL is the scan code
  mov ax, di
  mov [es:si], al
  ; Also increase the length of the buffer
  inc bx
  ; After inserting the data, check whether each is allowed; if not
  ; continue with the next char
  mov dx, [bp + 4]
  test dx, dx
  jne .next_scancode 
  ; Use DI as loop var to print
  mov di, si
.shift_right_loop_body:
  cmp di, bx
  je .shift_right_change_cursor
  mov al, [es:di]
  mov ah, [video_print_attr]
  call putchar
  inc di
  jmp .shift_right_loop_body
  ; Move the cursor back to the new location
.shift_right_change_cursor:
  call video_clearcursor
  ; Cursor also moves right by one together with the char
  inc si
  mov di, si
  ; Move back cursor to the right position
.shift_right_change_cursor_body:
  cmp di, bx
  je .after_shift_right_change_cursor
  inc di
  call video_move_to_prev_char
  jmp .shift_right_change_cursor_body
.after_shift_right_change_cursor:
  call video_putcursor
  jmp .next_scancode
.normal_return:
  ; Terminate the string
  mov byte [es:bx], 0
  ; Compute the actual number we have read
  mov ax, bx
  sub ax, [bp + 10]
.return:
  ; Protect return value
  mov si, ax
  mov al, 0ah
  call putchar
  mov ax, si
  pop di
  pop si
  pop bx
  pop es
  mov sp, bp
  pop bp
  retn
  ; This subroutine is private to the function; We use it to clear the buffer
  ; backwards (char by char, in case the screen scrolls up), and then
  ; print the new content of the buffer
.refresh_string:
  push si
  mov si, bx
  call video_clearcursor
  pop si

  ; This is the scan code buffer (128 byte, 64 entries currently)
kbd_scan_code_buffer: times KBD_BUFFER_CAPACITY dw 0
  ; This always points to the next location to push new code
kbd_scan_code_head:        dw 0
  ; This always points to the oldest valid code
kbd_scan_code_tail:        dw 0
kbd_scan_code_buffer_size: dw 0
; This status byte is updated
kbd_status:                db 0

; Only the first 127 entries are useful
; We currently only have 64 entries; In the future this table can be extended to
; support more
kbd_unshifted_scan_code_map: 
;  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
db 00h, 00h, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 00h, 00h   ; 0 
db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 00h, 00h, 'a', 's'   ; 1
db 'd', 'f', 'g', 'h', 'j', 'k', 'l', 3bh, 27h, '`', 00h, 5ch, 'z', 'x', 'c', 'v'   ; 2
db 'b', 'n', 'm', ',', '.', '/', 00h, 00h, 00h, 20h, 00h, 00h, 00h, 00h, 00h, 00h   ; 3
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 4
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 5
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 6
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 7

kbd_shifted_scan_code_map: 
;  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
db 00h, 00h, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 00h, 00h   ; 0 
db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 00h, 00h, 'A', 'S'   ; 1
db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', 22h, '~', 00h, '|', 'Z', 'X', 'C', 'V'   ; 2
db 'B', 'N', 'M', '<', '>', '?', 00h, 00h, 00h, 20h, 00h, 00h, 00h, 00h, 00h, 00h   ; 3
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 4
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 5
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 6
;db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 7
