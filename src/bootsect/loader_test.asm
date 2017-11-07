_loader_test_start:
;
; loader_test.asm - This file contains test cases for modules
;

disk_test:
  call disk_chs_test
  call disk_param_test
  call disk_buffer_test
  retn

disk_buffer_test:
  push es
  push si
  push bx
  mov si, DISK_BUFFER_MAX_ENTRY
  ; Load ES with the large BSS address
  mov ax, MEM_LARGE_BSS_SEG
  mov es, ax
.body:
  test si, si
  jz .return
  dec si
  call disk_find_empty_buffer
  mov bx, ax
  ; Set LBA - The first LBA is 15 and the last is 0
  mov word [es:bx + disk_buffer_entry.lba + 2], 0
  mov [es:bx + disk_buffer_entry.lba], si
  mov byte [es:bx + disk_buffer_entry.letter], 'A'
  mov byte [es:bx + disk_buffer_entry.device], 00h
  ; Push far pointer to the buffer for holding the sector
  push MEM_LARGE_BSS_SEG
  lea ax, [es:bx + disk_buffer_entry.data]
  push ax
  ; Push LBA
  push word 0
  push si
  push word 'A'
  call disk_read_lba
  add sp, 10
  jmp .body
.return:
  ; Here the last sector is sector 1 (LBA 0)
  mov ax, [es:bx + disk_buffer_entry.data + DISK_SECTOR_SIZE - 2]
  push ax
  push ds
  push .sector_end_str
  call video_printf
  add sp, 6
  pop bx
  pop si
  pop es
  retn
.sector_end_str: db "Sector end: %x", 0ah, 00h

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



