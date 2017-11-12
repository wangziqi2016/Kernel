_loader_bsod_start:
;
; loader_bsod.asm - This file contains a simple error handling machanism:
;                   Blue Screen of Death
;

; This is the character attr we use for printing in BSOD mode
BSOD_VIDEO_ATTR equ VIDEO_ATTR_FG_RED | VIDEO_ATTR_FG_HIGHLIGHT | VIDEO_ATTR_BG_BLUE

  ; This function never returns - so it can be either called, or directly 
  ; jumped onto. It receives video_printf() like parameters, and prints 
  ; the error on the screen
  ; 
  ; Note that this function has multiple entrances: we can choose to either
  ; clear the screen or not to clear
bsod_fatal:
  push bp
  mov bp, sp
  call video_clear_all
bsod_fatal_noclear:
  ; AL is now number of rows, we compute the total number of characters
  ; by multiplying these two
  mov al, byte [video_max_row]
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
  mov byte [es:bx], BSOD_VIDEO_ATTR
  inc bx
  inc bx
  jmp .body
.after_set_blue:
  ; Also change the attr we use for printing
  mov byte [video_print_attr], BSOD_VIDEO_ATTR
  mov ax, bsod_fatal_error_str
  call video_putstr_near
  ; Then call printf core to print them out
  mov ax, [bp + 6]
  push ax
  mov ax, [bp + 4]
  push ax
  ; Offset to the vector of arguments
  push word 18d
  call video_printf_core
  add sp, 6
  mov ax, bsod_press_key_to_reboot
  call video_putstr_near
  ; Use a loop to wait a valid scan code of any key
  ; on the keyboard, and then reboot
.wait_scan_code:
  call kbd_getscancode
  test al, al
  jz .wait_scan_code
  ; Soft reboot by jumping to FFFF:0000
  push 0ffffh
  push 0000h
  retf

bsod_fatal_error_str:     db "FATAL ERROR: ", 0ah, 00h
bsod_press_key_to_reboot: db "PRESS ANY KEY TO REBOOT...", 00h
  
  