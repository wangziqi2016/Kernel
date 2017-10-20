
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

section .text
  ; This file is loaded into BX=0200h as the second sector 
	org	0200h

  cli
  ; This is the new segment address
  push cs
  push cs
  ; DS and ES are both the same as CS because we can only do segment addressing
  pop ds
  pop es
  ; Reset the stack pointer to 0000:FFF0, i.e. the end of the first segment
  mov sp, 0FFF0h
  sti

  ; Refresh the screen
  call video_init
  call mem_init
  call kbd_init

  mov si, 400
  mov di, 4
  mov bx, 0775h
test_putchar:
  test si, si
  jnz print_char
  test di, di
  jz after_test_putchar
  mov si, 400
  dec di
  inc bl
print_char:
  mov ax, bx
  call putchar
  dec si
  jmp test_putchar

after_test_putchar:
  call video_move_to_next_line
  call video_clear_all

  push ds
  push str_load_success
  call video_putstr
  call video_putstr
  call video_putstr
  call video_putstr
  add sp, 4

  push word 1234h
  call video_puthex16
  add sp, 2
  mov al, 10
  call putchar
  push word 10000
  call video_putuint16
  add sp, 2
  mov al, 10
  call putchar
  push word 00FEh
  call video_puthex8
  add sp, 2

scancode_loop:
  call kbd_getscancode
  test ax, ax
  je scancode_loop
  call kbd_tochar
  test ah, KBD_UNPRINTABLE
  jne print_unprintable
  mov ah, 07h
  call putchar
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
