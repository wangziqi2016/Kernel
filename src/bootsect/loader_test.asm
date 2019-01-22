_loader_test_start:
;
; loader_test.asm - This file contains test cases for modules
;

disk_test:
  call disk_chs_test
  call disk_param_test
  retn

disk_param_test:
  push word 'A'
  call disk_getparam
  mov bx, ax
  pop ax
  mov ax, [bx + disk_param.capacity]
  mov dx, [bx + disk_param.capacity + 2]
  push dx
  push ax
  call video_putuint32
  add sp, 4
  jmp .return
.disk_size_error:
  mov ax, disk_get_size_error_str
  call video_putstr_near
.return:
  retn

  ; This function tests disk
disk_chs_test:
  push word 0
  push word 2879
  push word 'A'
  call disk_getchs
  add sp, 6
  push ax
  movzx ax, dl
  push ax
  movzx ax, dh
  push ax
  movzx ax, cl
  push ax
  movzx ax, ch
  push ax
  push ds
  push disk_chs_test_str
  call video_printf
  add sp, 14
  retn

printf_test:
  push dword 675973885
  push ds
  push printf_far_str
  push printf_near_str
  push word '@'
  push word 0abh
  push word 0cdefh
  push word -2468
  push word 12345
  push ds
  push printf_test_str
  call video_printf
  add sp, 24
  retn

printf_test_str: db "This is a test to printf %u %d %x %y %q %c %s %S %U %% %", 0ah, 00h
printf_near_str: db "NEAR", 00h
printf_far_str: db "FAR", 00h

disk_chs_test_str: db "CH = %y CL = %y DH = %y DL = %y AX = %x", 0ah, 00h
disk_get_size_error_str: db "Disk size error", 0ah, 00h

; The following can be used for debugging purposes
debug_U_str: db "%U", 0ah, 00h
debug_u_str: db "%u", 0ah, 00h
debug_x_str: db "%x", 0ah, 00h
debug_y_str: db "%y", 0ah, 00h
debug_X_str: db "%X", 0ah, 00h

