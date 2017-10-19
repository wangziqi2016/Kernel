
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
KBD_EXTENDED_ON     equ 20

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
  ; Note that for (1) we cannot do it in one call, because they are sent via 2
  ; interupts. We just set the extended flag, and clear it after we have 
  ; received the second byte in a later interrupt
kbd_isr:
  pusha
  push ds
  push es
  mov ax, [kbd_scan_code_buffer_size]
  cmp ax, KBD_BUFFER_CAPACITY
  je .full_buffer
  inc ax
  mov [kbd_scan_code_buffer_size], ax
  ; If head cannot be written into, we wrap back to index = 0
  ; Otherwise just use head
  mov ax, [kbd_scan_code_head]
  cmp ax, KBD_BUFFER_CAPACITY
  jne .read_port
  xor ax, ax
.read_port:
  ; Compute the target address in the buffer in BX
  ;   BX = base + index * 2
  ; because each entry is 2 byte
  mov bx, kbd_scan_code_buffer
  shl ax, 1
  add bx, ax
  ; Move the head to the next location and store it back
  inc ax
  mov [kbd_scan_code_head], ax
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
.process_extended_flag:
  or byte [kbd_status], KBD_EXTENDED_ON
  jmp .finish_interrupt
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
.process_ctrl_up:
.finish_interrupt
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
.return:
  pop es
  pop ds
  ; Note that SP is ignored
  popa
  iret
  
  ; This function is non-blocking
  ; It returns a scan code from the buffer in AL; If the buffer is empty it 
  ; returns 0 in AL. AH is cleared to 0
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
  mov bx, kbd_scan_code_buffer
  add bx, ax
  ; Increment and write back the index first
  inc ax
  mov [kbd_scan_code_tail], ax
  ; Read the scan code
  movzx ax, byte [bx]
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
  sti
  retn

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
kbd_scan_code_map: 
;  1    2    3    4    5    6    7    8    9    A    B    C    D    E
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 1 
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 2
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 3
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 4
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 5
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 6
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 7
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h   ; 8