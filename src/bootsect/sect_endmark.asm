
;
; loader_endmark.asm - This file defines the padding and marker bytes for 
;                      the end of the loader
;

END_MARK equ 0abcdh
; Pad 0 byte until we reached a multiple of 512
; $ means the current offset (taking the org into account) and $$ means the beginning of the section
; Note that $$ evaluates to 200 since the text section org is set to 0x200
times (512 - (($-$$) % 512) - 6) db 0               ; This will throw warning if value is negative
endmark_total_byte: dw 512 * (($ - $$ + 511) / 512) ; This is the number of bytes
endmark_total_sect: dw ($ - $$ + 511) / 512         ; This is the number of sectors
endmark_endmark:    dw END_MARK                     ; This is the loader end mark
