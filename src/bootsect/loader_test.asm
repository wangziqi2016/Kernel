_loader_test_start:
;
; loader_test.asm - This file contains test cases for modules
;

disk_test:
  ;call disk_chs_test
  ;call disk_param_test
  xor ax, ax                        ; Pass LBA in AX (low 16 bits)
  call disk_op_test
  mov ax, [endmark_total_sect]
  dec ax
  call disk_op_test
  call disk_buffer_test
  call dist_rw_test
  call fat12_getnext_test
  retn

disk_param_test:
  mov al, 'A'
  call disk_getparam
  mov bx, ax
  push word [bx + disk_param.capacity + 2]
  push word [bx + disk_param.capacity]
  push .str
  call video_printf_near
  add sp, 6
.return:
  retn
.str: db "Disk A size: %U", 0ah, 00h

  ; This function tests disk
disk_chs_test:
  push si
  mov si, 2881   ; 2879 is the last valid sector, we will see two invalid returns
.repeat_chs:
  push word 0
  push si
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
  push disk_chs_test_str
  call video_printf_near
  add sp, 12
  dec si
  cmp si, 2869
  jae .repeat_chs
  pop si
  retn

; Load LBA stored in AX
disk_op_test:
  sub sp, 512
  mov bp, sp          ; Use BP to address the temp var
  push ss
  push bp
  push word 0
  push ax
  push word 'A'
  push DISK_OP_READ
  call disk_op_lba
  push ax             ; Returned status code
  mov ax, [bp + 510]  ; Where the signature should be
  push ax
  push .str
  call video_printf_near
  add sp, 530         ; It clears stack for two func calls and the temp var
  ret
.str: db "Signature: %x (AX %u)", 0ah, 00h

disk_buffer_test:
  push si
  mov ax, DISK_DEBUG_NONE
  call disk_print_buffer
  mov si, 18
.load_1:
  test si, si
  jz .finish_load_1
  push word 0
  push si
  push word 'A'
  call disk_insert_buffer
  add sp, 6
  dec si
  jmp .load_1
.finish_load_1:
  push word 1234h
  push word 5678h
  push word 'A'           ; Change this for wrong letter
  call disk_insert_buffer ; Tests invalid LBA on disk 'A'
  push ax                 ; AX will be destroyed below, so push it here
  mov ax, DISK_DEBUG_NONE
  call disk_print_buffer
  push .str1
  call video_printf_near  ; Print AX = 4 (invalid LBA)
  add sp, 10
.return:
  pop si
  ret
.str1: db "AX = %u", 0ah, 00h

; Tests whether disk_read_word works
dist_rw_test:
  push 1234h
  push word 0
  push word 511
  push word 'A'
  mov ax, DISK_OP_WRITE
  call disk_op_word
  call helper_print_ax_cf                  ; Should print "1234", 0xAA from previous sect, 0xFA from next
  mov ax, DISK_OP_READ
  call disk_op_word
  call helper_print_ax_cf                  ; Should print "1234", the value we wrote
  mov ax, DISK_DEBUG_EVICT                 ; Tests force evict
  call disk_print_buffer
  add sp, 8                                ; Clears two disk_op_word arguments
  ret

; This helper function prints AX and CF value. Must be called immediately after 
; the call returns.
helper_print_ax_cf:
  setc cl
  xor ch, ch
  push cx
  push ax
  push .str1
  call video_printf_near
  add sp, 6                                ; Clears printf arguments
  ret
.str1: db "AX = %x, CF = %u", 0ah, 00h

; Tests FAT 12 getnext() function
fat12_getnext_test:
  push si
  mov si, 2
.body:
  cmp si, 20                               ; Test first 20 sectors (clusters)
  je .return
  mov ax, si
  call fat12_getnext
  call helper_print_ax_cf
  inc si
  jmp .body
.return:
  pop si
  ret

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


