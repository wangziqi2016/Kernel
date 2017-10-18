
;
; loader_mem.asm - This file contains memory functions
;

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