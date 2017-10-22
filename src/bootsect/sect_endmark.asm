
;
; loader_endmark.asm - This file defines the padding and marker bytes for 
;                      the end of the loader
;

END_MARK equ 0abcdh
; Pad 0 byte until we reached a multiple of 512
times (512 - (($-$$) % 512) - 2) db 0
; This is the loader end mark
dw END_MARK
