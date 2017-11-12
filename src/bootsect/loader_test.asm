_loader_test_start:
;
; loader_test.asm - This file contains test cases for modules
;

disk_test:
  call disk_chs_test
  call disk_param_test
  call disk_buffer_test
  retn

  ; AX = index
  ; return: AX = offset
disk_buffer_get_ptr:
  xor dx, dx
  mov cx, disk_buffer_entry.size
  mul cx
  add ax, [disk_buffer]
  retn

disk_buffer_test:
  push es
  push si
  push bx
  mov si, DISK_BUFFER_MAX_ENTRY + 10
  ; Load ES with the large BSS address
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
.body:
  test si, si
  jz .return
  dec si
  ; Arguments
  push 0
  push si
  push 'A'
  call disk_get_sector
  add sp, 6
  ; Call to print the cirlular buffer
  call disk_buffer_print
  jmp .body
.return:
  ; Change it and write back
  mov word [es:bx + disk_buffer_entry.data + DISK_SECTOR_SIZE - 2], 0aabbh
  mov ax, bx
  call disk_buffer_write_lba
  jc .error_rw
  ; Print the status
  mov al, [es:bx + disk_buffer_entry.status]
  push ax
  ; Here the last sector is sector 1 (LBA 0)
  mov ax, [es:bx + disk_buffer_entry.data + DISK_SECTOR_SIZE - 2]
  push ax
  push ds
  push .sector_end_str
  call video_printf
  add sp, 8
.test_buffer_access:
  mov ax, 0
  call disk_buffer_get_ptr
  call disk_buffer_access
  mov ax, 9
  call disk_buffer_get_ptr
  call disk_buffer_access
  mov ax, 12
  call disk_buffer_get_ptr
  call disk_buffer_access
  mov ax, 10
  call disk_buffer_get_ptr
  call disk_buffer_access
  call disk_buffer_print
.test_disk_flush:
  mov ax, 10
  call disk_buffer_get_ptr
  call disk_buffer_flush
  mov ax, 0
  call disk_buffer_get_ptr
  call disk_buffer_flush
  mov ax, 5
  call disk_buffer_get_ptr
  call disk_buffer_flush
  mov ax, 11
  call disk_buffer_get_ptr
  call disk_buffer_flush
  call disk_buffer_print
.test_disk_flush_all:
  call disk_buffer_flush_all
  call disk_buffer_print
  pop bx
  pop si
  pop es
  retn
.error_rw:
  push ax
  push ds
  push .error_rw_disk_str
  call video_printf
.die:
  jmp .die
.sector_end_str: db "Sector end: %x; status = %y", 0ah, 00h
.error_rw_disk_str: db "Error r/w disk (AX = 0x%x)", 0ah, 00h

disk_param_test:
  push word 'A'
  call disk_get_size
  pop cx
  jc .disk_size_error
  push dx
  push ax
  call video_putuint32
  add sp, 4
  push word 'A'
  call disk_get_param
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
  call disk_get_chs
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



