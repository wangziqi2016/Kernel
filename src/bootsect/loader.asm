_loader_start:
;
; loader.asm - The stage I loader
;
; This file provides basic I/O functions. All functions are called
; with CDECL convention, i.e. AX, CX, DX are caller saved, parameters
; are pushed from right to left, and the caller is responsible for clearing
; the stack
;
; Note that this function has several modules, which are concatenated to
; this file during the compilation stage. 
;
; Some other rules for writing the loader module:
;   1. Each file should end with a new line. This is to avoid "cat" mixing 
;      lines from two files
;   2. At line #1 of each file, there must be a "_[file name]_start" label. This
;      label is used by the parser to translate a line # in the combined
;      file to a line # in the corresponding file
;   3. Do not define any segment
;   4. Each module should always name their own label using a unique prefix,
;      e.g. video_, kbd_, mem_, etc.
;   5. For asynchronous interrupt service routines, do not assume what DS and
;      ES and SS would be; instead, if you need to access data via DS,
;      the ISR should save the old segment register and load them with the 
;      corresponding registers
;   6. For system routines other than ISR, always assume that DS points to 
;      the system data segment, but do not assume about ES or SS
;      If these routines are called by user programs, the common prologue
;      should ensure that the condition holds true
;

SYS_DS equ 1000h
SYS_SS equ 0h

section .text
  ; This file is loaded into BX=0200h as the second sector 
	org	0200h

  cli
  ; DS = system segment address
  mov ax, SYS_DS
  mov ds, ax
  ; Initialize SS and SP to point to the end of the first 64K segment
  mov ax, SYS_SS
  mov ss, ax
  ; Reset the stack pointer to 0000:FFF0, i.e. the end of the first segment
  mov sp, 0FFF0h
  sti

  ; Call initialization routines
  call video_init
  call mem_init
  call kbd_init
  call disk_init

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
  push .chs_test_str
  call video_printf
  add sp, 12
  jmp .after_chs_test
  .chs_test_str: db "CH = %y CL = %y DH = %y DL = %y AX = %x", 0ah, 00h
.after_chs_test:
  push ds
  push .printf_far_str
  push .printf_near_str
  push word '@'
  push word 0abh
  push word 0cdefh
  push word -2468
  push word 12345
  push ds
  push .printf_test_str
  call video_printf
  add sp, 16
  jmp test_disk_param
  .printf_test_str: db "This is a test to printf %u %d %x %y %q %c %s %S %% %", 0ah, 00h
  .printf_near_str: db "NEAR", 00h
  .printf_far_str: db "FAR", 00h
test_disk_param:
  push word 'A'
  call disk_get_size
  pop cx
  jc disk_size_error
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
  jmp getline_loop
disk_size_error:
  mov ax, .get_disk_size_error_str
  call video_putstr_near
  jmp getline_loop
  .get_disk_size_error_str: db "Disk size error", 0ah, 00h
getline_loop:
  push ds
  push test_buffer
  push word 100
  xor ax, ax
  push ax
  call kbd_getinput
  add sp, 8
  cmp ax, 0ffffh
  je .interupted
  mov ax, test_buffer
  call video_putstr_near
  jmp .continue
.continue:
  mov al, 0ah
  call putchar
  jmp getline_loop
.interupted:
  mov ax, str_interrupted
  call video_putstr_near
  jmp getline_loop
test_buffer: times 64 db 0
str_interrupted: db "CTRL+C", 0ah, 00h
scancode_loop:
  call kbd_getscancode
  test ax, ax
  je scancode_loop
  call kbd_tochar
  test ah, KBD_EXTENDED_ON
  jne process_extended
test_unprintable:
  test ah, KBD_UNPRINTABLE
  jne print_unprintable
  mov ah, 07h
  call putchar
  jmp scancode_loop
process_extended:
  ; Left arrow
  cmp al, KBD_EXTENDED_ARROW_LEFT
  je process_left_arrow
  cmp al, KBD_EXTENDED_ARROW_RIGHT
  je process_right_arrow
  jmp test_unprintable
process_left_arrow:
  call video_clearcursor
  call video_move_to_prev_char
  call video_putcursor
  jmp scancode_loop
process_right_arrow:
  call video_clearcursor
  call video_move_to_next_char
  call video_putcursor
  jmp scancode_loop
print_unprintable:
  ; Save AX in a safe place
  mov bx, ax
  movzx dx, bl
  push dx
  call video_puthex8
  add sp, 2
  mov al, '-'
  mov ah, 07h
  call putchar
  movzx dx, bh
  push dx
  call video_puthex8
  add sp, 2
  mov al, ' '
  mov ah, 07h
  call putchar
  jmp scancode_loop

die:
  jmp die
