_loader_mem_start:
;
; loader_mem.asm - This file contains memory functions
;

  ; This function initializes memory management
mem_init:
  ; If A20 is enabled, then we continue with other jobs
  call mem_check_a20
  test ax, ax
  jnz .a20_ok
  mov ax, mem_a20_closed_str
  call video_putstr_near
  call mem_enable_a20_via_8042
  call mem_check_a20
  test ax, ax
  jnz .a20_ok
  mov ax, mem_a20_failed_str
  call video_putstr_near
  ; If A20 cannot be activalted just die here
.die:
  jmp die
.a20_ok:
  mov ax, mem_a20_opened_str
  call video_putstr_near
.detect_high_addr:
  ; Store the value in memory
  call mem_detect_conventional
  mov ax, mem_high_end_str
  call video_putstr_near
  mov ax, [mem_high_end]
  push ax
  call video_putuint16
  pop ax
  ; New line
  mov ax, 070ah
  call putchar
.after_a20:
  retn

  ; This function queries the BIOS for the highest address currently
  ; addressable in the system and store it in mem_high_end
mem_detect_conventional:
  xor ax, ax
  ; No param
  int 12h
  jc .error
  mov [mem_high_end], ax
  retn
.error:
  mov ax, mem_int12h_err_str
  call video_putstr_near
.die:
  jmp .die
  

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

  ; This function ebales A20 gate using keyboard 8042 MIC
  ; http://www.win.tue.nl/~aeb/linux/kbd/A20.html
mem_enable_a20_via_8042:
  call .empty_8042
  mov al, 0d1h
  out 64h, al
  call .empty_8042
  mov al, 0dfh
  out 60h, al
  call .empty_8042
  retn
.empty_8042:
  in al, 64h
  test al, 02h
  jnz .empty_8042
  retn

  ; This function copies memory regions that are not overlapped
  ;   [SP + 0] - Dest offset
  ;   [SP + 2] - Dest segment
  ;   [SP + 4] - Source offset
  ;   [SP + 6] - Source segment
  ;   [SP + 8] - Length
  ; Note that this function must be executed atomically, because we 
  ; changed the DS register. If an interrupt comes when this function is
  ; being executed, then the interrupt will use the wrong DS register
  ; to generate address for static data structures
memcpy_nonalias:
  cli
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
  sti
  retn

  ; This function shifts a region by some given amount
  ; Note that we assume the data to be shifted are in the same segment
  ; and therefore, only one segment argument is required
  ;   [SP + 0] - Offset
  ;   [SP + 2] - Segment
  ;   [SP + 4] - Length
  ;   [SP + 6] - Shift amount (to higher address)
memshift_tohigh:
  push bp
  mov bp, sp
  push es
  push si
  push di

  mov ax, [bp + 6]
  mov es, ax
  ; SI = source end DI = dest end
  ; CX = length of the source
  mov si, [bp + 4]
  mov cx, [bp + 8]
  add si, cx
  mov di, si
  add di, [bp + 10]
  ; We copy from high to low
  ; Also there is no word-optimization
.body:
  test cx, cx
  je .return
  dec cx
  dec si
  dec di
  mov al, [es:si]
  mov [es:di], al
  jmp .body
.return:
  pop di
  pop si
  pop es
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

mem_a20_closed_str: db "A20 gate is by default closed.", 0ah, 00h
mem_a20_opened_str: db "A20 gate is now activated.", 0ah, 00h
mem_a20_failed_str: db "Cannot activate A20 gate. Die.", 0ah, 00h
mem_high_end_str:   db "Conventional memory size (KiB): ", 00h
mem_int12h_err_str: db "INT12H error", 0ah, 00h

; This defines the system high end between 0 and 1MB range
; 0xA0000 is a reasonable guess, but we will use INT15H to decide
; the actual value on mem initialization
mem_high_end:   dw 0280h
