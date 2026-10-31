;=======================================================================================
; gfx.asm - screen setup for Archon65 (on top of lib/video_fcm.asm).
;
;   gfx_init       Full Colour 320x200, double-buffered; loads the generated 256-colour
;                  palette (src/gen/palette.asm) through lib/palette.asm
;   box            filled rectangle: box_x (word), box_y, box_w, box_h, A = colour
;
; Text is lib/fcm_text.asm with the 8x8 font (src/assets/font.asm); the static
; backgrounds of the board and the arena are kept by lib/fcm_cache.asm.
;=======================================================================================

FTEXT_FONT      = font8

box_x:          .word 0
box_y:          .byte 0
box_w:          .byte 0
box_h:          .byte 0

gfx_init:
        jsr fcm_init
        lda #<palette_rgb
        sta pal_src
        lda #>palette_rgb
        sta pal_src+1
        lda #0                          ; 0 = all 256 entries
        sta pal_count
        lda #255
        jmp pal_set_level

box:
        sta draw_col
        lda box_x
        sta draw_x0
        lda box_x+1
        sta draw_x0+1
        lda box_y
        sta draw_y0
        lda box_w
        sta draw_w
        lda #0
        sta draw_w+1
        lda box_h
        sta draw_h
        jmp draw_fill
