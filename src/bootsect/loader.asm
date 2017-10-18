
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
  call video_putline
  call video_putline
  call video_putline
  call video_putline
  add sp, 4

die:
  jmp die
