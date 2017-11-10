_loader_bsod_start:
;
; loader_bsod.asm - This file contains a simple error handling machanism:
;                   Blue Screen of Death
;

  ; This function never returns - so it can be either called, or directly 
  ; jumped onto. It receives video_printf() like parameters, and prints 
  ; the error on the screen
bsod_fatal:
  mov ax, [video_max_row]
  push ax
  call video_scroll_up
  ; AL is now number of rows, we compute the total number of characters
  ; by multiplying these two
  pop ax
  mov ah, byte [video_max_col]
  mul ah
  mov cx, ax
  xor bx, bx
  mov ax, VIDEO_SEG
  mov es, ax
  ; BX points to attr
  inc bx
  ; We set the bg color to blue
.body:
  test cx, cx
  je .after_set_blue
  dec cx
  ; Blue bg and red + high light fg
  mov byte [es:bx], 79h
  
  