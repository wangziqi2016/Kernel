
;
; loader_endmark.asm - This file defines the padding and marker bytes for 
;                      the end of the loader
;

END_MARK equ 0abcdh
; Pad 0 byte until we reached a multiple of 512
; $ means the current offset (taking the org into account) and $$ means the beginning of the section
; Note that $$ evaluates to 200 since the text section org is set to 0x200
BYTES_REMAINING equ 512 - (($-$$) % 512) ; Number of bytes remaining to reach 512 bytes boundary
TOTAL_SECT      equ ($-$$ + 512 + 511) / 512
TOTAL_BYTE      equ 512 * TOTAL_SECT
%if BYTES_REMAINING >= 6
times (BYTES_REMAINING - 6) db 0         ; End of sector - normal case
ACTUAL_TOTAL_BYTE equ TOTAL_BYTE
ACTUAL_TOTAL_SECT equ TOTAL_SECT
%else
times (BYTES_REMAINING + 512 - 6) db 0   ; End of sector - pad one more sector and add the ending marks
ACTUAL_TOTAL_BYTE equ TOTAL_BYTE + 512
ACTUAL_TOTAL_SECT equ TOTAL_SECT + 1
%endif

endmark_total_byte: dw ACTUAL_TOTAL_BYTE ; This is the number of bytes
endmark_total_sect: dw ACTUAL_TOTAL_SECT ; This is the number of sectors
endmark_endmark:    dw END_MARK          ; This is the loader end mark
endmark_code_size:                       ; Symbolic ending of the code segment
