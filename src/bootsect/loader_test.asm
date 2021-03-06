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
  call fat12_readdir_test
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
  mov ax, 'B'
  call fat12_open                          ; Returns the pointer to fat12_param
  jc .err
  push ax                                  ; fat12_getnext takes this as stack arg
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
  pop ax
  pop si
  ret
.err:
  push ds
  push .str1
  call bsod_fatal
.str1: db "fat12 open error", 0ah, 00h

; Tests fat12_readdir
fat12_readdir_test:
  push bp
  sub sp, FAT12_DIR_LENGTH               ; Local var for one dir entry
  mov bp, sp                             ; Use BP to access the dir entry
  mov ax, 'B'
  call fat12_open
  jc .err
  push ss                                ; BP - 2
  push bp                                ; BP - 4 Dest buffer -> Note do not use SP b/c it has changed
  push dx                                ; BP - 6
  push cx                                ; BP - 8
  push ax                                ; BP - 10 Two tokens, one for root another for FAT12
.body:
  push word [bp - 8]
  push word [bp - 6]
  push .str1
  call video_printf_near
  add sp, 6
  call fat12_readdir
  jc .err
  test ax, ax
  jnz .return
  mov byte [bp + 11], 00h               ; Ending entry with \n\0 (8.3 file name ends at 11)
  push word [bp + 30]
  push word [bp + 28]
  push ss
  push bp
  push .str2
  call video_printf_near
  add sp, 10
  jmp .body
.str1: db "DX:CX %u:%u", 0ah, 00h
.str2: db "%S %U", 0ah, 00h
.return:
  add sp, FAT12_DIR_LENGTH + 10
  pop bp
  ret
.err:
  push ds
  push .str
  call bsod_fatal
.str: db "fat12_readdir err", 0ah, 00h

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


