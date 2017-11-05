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
  
  push 12345
  push ds
  push .printf_test_str
  call video_printf
  add sp, 6
  jmp getline_loop
  .printf_test_str: db "This is a test to printf %u %d %", 0ah, 00h
;  mov si, 400
;  mov di, 4
;  mov bx, 0775h
;test_putchar:
;  test si, si
;  jnz print_char
;  test di, di
;  jz after_test_putchar
;  mov si, 400
;  dec di
;  inc bl
;print_char:
;  mov ax, bx
;  call putchar
;  dec si
;  jmp test_putchar
;
;after_test_putchar:
;  call video_move_to_next_line
;  call video_clear_all

;  push ds
;  push str_load_success
;  call video_putstr
;  call video_putstr
;  call video_putstr
;  call video_putstr
;  add sp, 4
;
;  push word 1234h
;  call video_puthex16
;  add sp, 2
;  mov al, 10
;  call putchar
;  push word 10000
;  call video_putuint16
;  add sp, 2
;  mov al, 10
;  call putchar
;  push word 00FEh
;  call video_puthex8
;  add sp, 2
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
