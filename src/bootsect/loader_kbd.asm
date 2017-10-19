
;
; loader_kbd.asm - This file implements the keyboard driver
;

KBD_BUFFER_CAPACITY equ 64

  ; This function intializes the keyboard interrupt
kbd_init:
  push es
  push bx
  cli

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
  mov bx, kbd_scan_code_buffer
  add bx, ax
  ; Move the head to the next location and store it back
  inc ax
  mov [kbd_scan_code_head], ax
  ; Read from port 0x60
  in al, 60h
  mov [bx], al
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
  ; Do nothing here temporarily
.return:
  pop es
  pop ds
  ; Note that SP is ignored
  popa
  iret

  ; This is the scan code buffer
kbd_scan_code_buffer: times KBD_BUFFER_CAPACITY db 0
  ; This always points to the next location to push new code
kbd_scan_code_head:        db 0
  ; This always points to the oldest valid code
kbd_scan_code_tail:        db 0
kbd_scan_code_buffer_size: dw 0

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