
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
; we know it is up
KBD_KEY_UP          equ 80h

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
  test ah, KBD_CAPS_LOCK
  jne .use_shift_table
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
.return:
  pop bx
  retn
  ; This branch sets the unprintable flag and return
.return_not_a_char:
  or ah, KBD_UNPRINTABLE
  jmp .return

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
kbd_unshifted_scan_code_map: 
;  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
db 00h, 00h, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 00h, 00h   ; 0 
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 1
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 2
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 3
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 4
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 5
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 6
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 7

kbd_shifted_scan_code_map: 
;  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
db 00h, 00h, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 00h, 00h   ; 0 
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 1
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 2
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 3
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 4
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 5
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 6
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 7