;=======================================================================================
; Project base-page variables, after the library's (lib/zp.asm). Keep below $90 if the
; program loads files with the KERNAL at boot.
;=======================================================================================
        .virtual LIB_ZP_END
str_ptr:        .word ?                 ; a pointer for table walks (ai.asm)
l_sv_ptr:       .word ?                 ; sound.asm (IRQ only): stream being read
zp_end:
        .endv
        .cerror zp_end > $90, "base page variables overflow into KERNAL space"
