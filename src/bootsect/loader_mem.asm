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
  ; Otherwise just die
  push ds
  mov ax, mem_a20_failed_str
  push ax
  call bsod_fatal
  ; NEVER RETURNS
  ;--------------
.a20_ok:
  mov ax, mem_a20_opened_str
  call video_putstr_near
.detect_high_addr:
  call mem_detect_conventional ; Store the value in [mem_high_end]
  push endmark_code_size       ; Loader size in bytes
  push word [mem_high_end]     ; Conventional memory size
  push mem_high_end_str        ; Format string accepting %d %d
  call video_printf_near       ; Print [mem_high_end]
  add sp, 6
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
  push ds
  mov ax, mem_int12h_err_str
  push ax
  call bsod_fatal

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
  ; Note that this function changes the DS register. This is fine for ISR
  ; as ISR will save DS and load it with sys DS value.
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

  ; Same as memshift_tohigh() except that it shifts towards the lower address
  ;   [SP + 0] - Offset
  ;   [SP + 2] - Segment
  ;   [SP + 4] - Length
  ;   [SP + 6] - Shift amount (to lower address)
memshift_tolow:
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
  mov di, si
  sub di, [bp + 10]
  ; We copy from high to low
  ; Also there is no word-optimization
.body:
  test cx, cx
  je .return
  mov al, [es:si]
  mov [es:di], al
  dec cx
  inc si
  inc di
  jmp .body
.return:
  pop di
  pop si
  pop es
  mov sp, bp
  pop bp
  retn

; This function sets a chunk of memory as a given byte value
;   [BP + 4]  - Offset
;   [BP + 6]  - Segment
;   [BP + 8]  - Value (should be a zero-extended byte)
;   [BP + 10] - Length
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

  ; This function allocates some memory for uninitialized static data
  ; at the end of the system data segment. Size = 0 will return the last returned value
  ; No overflow checking except for wrap-back
  ;   AX = number of bytes to allocate
  ; Return：
  ;   AX = 0FFFFh if fails, AX = offset of start if succeeds
  ;   CF is set if fails also
mem_get_sys_bss:
  cli
  cmp ax, [mem_sys_bss]
  ja .bss_overflow      ; Cannot wrap back
  mov cx, ax
  mov ax, [mem_sys_bss] ; AX = Old value; CX = Requested size
  sub [mem_sys_bss], cx ; Move the pointer
  sub ax, cx
  inc ax                ; Ret = old - size + 1
  cmp ax, [endmark_total_byte] ; If AX is below the size of the code segment then it is overflow
  jb .bss_overflow      ; If the number of bytes exceeds what was left then print error
  clc                   ; Return no error
  jmp .return
.bss_overflow:
  add [mem_sys_bss], cx ; Restore the previous value
  xor ax, ax
  dec ax
  stc
.return:
  sti
  retn

  ; This function allocates a requested chunk from the large BSS section
  ; Large BSS is at the high end of memory with A20 opened, i.e. FFFF:0010
  ; to FFFF:FFFF. The semantics of this function is very similar to 
  ; mem_get_sys_bss.
  ;   AX = number of bytes to allocate. We check for wrap-back
  ; Return:
  ;   AX = 0x0000 if fails, AX = offset address
  ;   CF is cleared if fails. CF is set if success
mem_get_large_bss:
  cli
  ; CX = 0x10000 - top, i.e. remaining bytes
  ; AX is the requested size
  mov cx, [mem_large_bss]
  neg cx
  ; If requested bytes > remaining bytes then we fail
  cmp ax, cx
  ja .return_fail
  neg cx
  ; AX is the pointer after allocation and we write it back
  add ax, cx
  mov [mem_large_bss], ax
  ; This is the value we return
  mov ax, cx
  clc
  jmp .return
.return_fail:
  xor ax, ax
  stc
.return:
  sti
  retn

mem_a20_closed_str:  db "A20 gate is by default closed.", 0ah, 00h
mem_a20_opened_str:  db "A20 gate is now activated.", 0ah, 00h
mem_a20_failed_str:  db "Cannot activate A20 gate. Die.", 0ah, 00h
mem_high_end_str:    db "Conventional memory size (KiB): %d, Loader size: %d", 0ah, 00h
mem_int12h_err_str:  db "INT12H error", 0ah, 00h

; This defines the system high end between 0 and 1MB range
; 0xA0000 is a reasonable guess, but we will use INT15H to decide
; the actual value on mem initialization (280h = 640d, unit is KB)
mem_high_end:   dw 0280h
; This is the static data in-segment offset. When we allocate memory
; for this routine, we decrement this counter
; Note that this area is located at the end of the system data segment
; and never frees (holds static system data)
mem_sys_bss:    dw 0ffffh
; This is the same as system BSS except that it uses the last segment 
; (A20 enabled).
; Note that we need to start allocating from 0x10, which is the first byte 
; after 1MB
mem_large_bss:  dw 0010h
