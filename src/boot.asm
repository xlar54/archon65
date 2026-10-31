;=======================================================================================
; boot.asm - load every asset file into attic RAM while the KERNAL still works.
;
;   boot_load      walks the generated manifest (src/gen/manifest.asm): each packed file
;                  goes to its attic address through lib/unpack.asm. Prints a dot per
;                  file; on a failure prints the message and stops. Call before #TAKEOVER.
;=======================================================================================

boot_load:
        lda #<str_loading
        ldy #>str_loading
        jsr print
        lda #0
        sta l_bl_i
_next:  ldx l_bl_i
        cpx #asset_count
        beq _done
        lda asset_attic0,x
        sta ld_attic
        lda asset_attic1,x
        sta ld_attic+1
        lda asset_attic2,x
        sta ld_attic+2
        lda asset_attic3,x
        sta ld_attic+3
        lda asset_len_lo,x
        sta ld_len
        lda asset_len_hi,x
        sta ld_len+1
        lda asset_name_hi,x
        tay
        lda asset_name_lo,x
        pha
        lda asset_name_len,x
        plx
        jsr load_packed_to_attic
        bcs _fail
        lda #<str_dot
        ldy #>str_dot
        jsr print
        inc l_bl_i
        bra _next
_done:  rts
_fail:  lda #<str_failed
        ldy #>str_failed
        jsr print
-       bra -
l_bl_i:         .byte 0

str_loading:    .null 13, "ARCHON 65 LOADING"
str_dot:        .null "."
str_failed:     .null 13, "LOAD FAILED - CHECK THE DISK"
