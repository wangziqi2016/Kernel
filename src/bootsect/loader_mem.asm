
;
; loader_mem.asm - This file contains memory functions
;

  ; This function initializes memory management
mem_init:
  ;in al, 0x92
  ;or al, 2
  ;out 0x92, al

  ;mov     ax,2401h                ;--- A20-Gate Activate ---
  ;int     15h

  ; If A20 is enabled, then we continue with other jobs
  call mem_check_a20
  test ax, ax
  jnz .a20_ok
  push ds
  push word mem_a20_closed
  call video_putstr
  add sp, 4
  jmp .after_a20
.a20_ok:
  push ds
  push word mem_a20_opened
  call video_putstr
  add sp, 4
.after_a20:
  retn

  ; This function checks whether A20 is there
  ; The way we check it is to verify that the memory address
  ; with wrap-around (using ES=0xFFFF) and without (using DS=0x0000)
  ; are actually the same. To be convenient, we use the bootloader's
  ; 0xAA55 flag as an anchor.
  ;
  ; Note that QEMU and Bochs will automatically enable A20, while
  ; VirtualBox does not.
  ;
  ; Returns AX=0 if not enabled; Otherwise AX=1
mem_check_a20:
  push ds
  push es
  push bx
  ; DS = 0; ES = 0xFFFF
  xor ax, ax
  push ax 
  pop ds
  push word 0ffffh
  pop es
  ; This is the location of the bootloader's 0xAA55
  mov bx, 7dfeh
  ; CX, DX holds values from DS ans ES respectively
  mov cx, [ds:bx]
  mov bx, 7e0eh
  mov dx, [es:bx]
  cmp cx, dx
  jne .return_has_a20
  ; Second test is to use another value
  mov bx, 7dfeh
  mov word [ds:bx], 1234h
  mov bx, 7e0eh
  mov dx, [es:bx]
  cmp dx, 1234h
  je .return_no_a20
  jmp .return_has_a20
.return_no_a20:
  xor ax, ax
  jmp .return
.return_has_a20:
  xor ax, ax
  inc ax
.return:
  pop bx
  pop es
  pop ds
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

mem_a20_closed: db "A20 gate is by default closed.", 0ah, 00h
mem_a20_opened: db "A20 gate is now activated.", 0ah, 00h