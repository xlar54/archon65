;=======================================================================================
; title.asm - the title and options screen, and the end of a game.
;
;   title_run      shows the options until F7 / fire: F3 cycles two players, computer
;                  Light, computer Dark; F5 who moves first. After DEMO_WAIT frames
;                  without a key the computer plays both sides (opt_cpu = 3).
;   title_draw     the scene (SCENE_TITLE)
;   game_over      shows game_result on the board for a while
;=======================================================================================

DEMO_WAIT       = 50 * 20               ; 20 s of idle title -> demo game
OVER_FRAMES     = 50 * 5

LOGO_RISE       = 150                   ; pixels below its place the logo starts
LOGO_GLINT      = 6                     ; frames per step of the glint

logo_rise:      .byte 0
l_glint:        .byte 0
l_glint_t:      .byte 0

opt_players:    .byte 0                 ; 0 two players, 1 computer Light, 2 computer Dark
title_idle:     .word 0
demo:           .byte 0

title_run:
        lda #SCENE_TITLE
        sta scene
        lda #0
        sta title_idle
        sta title_idle+1
        sta demo
        lda #LOGO_RISE                  ; the logo rises into place
        sta logo_rise
        jsr music_title
_wait:  jsr frame
        jsr logo_animate
        inc title_idle
        bne +
        inc title_idle+1
+
        lda frame_key
        cmp #K_F3
        bne +
        lda opt_players
        inc a
        cmp #3
        bcc _p
        lda #0
_p:     sta opt_players
        bra _key
+       cmp #K_F5
        bne +
        lda opt_first
        eor #1
        sta opt_first
        bra _key
+       cmp #K_F7
        beq _start
        lda joy_new
        and #JOY_FIRE
        bne _start
        lda dbg_script_on               ; (no demo while a test script runs)
        bne _key
        lda title_idle+1                ; idle long enough: a demo game
        cmp #>DEMO_WAIT
        bcc _wait
        lda #3
        sta opt_cpu
        lda #1
        sta demo
        bra _go
_key:   lda #0
        sta title_idle
        sta title_idle+1
        bra _wait
_start: ldx opt_players
        lda l_cpu_bits,x
        sta opt_cpu
_go:    jmp music_stop
l_cpu_bits:     .byte 0, 1, 2

; the title animation: the logo rises 3 pixels a frame, then a glint runs down its five
; golds (palette entries COL_LOGO0-4, restored from the palette tables each step)
logo_animate:
        lda logo_rise
        beq _glint
        sec
        sbc #3
        bcs +
        lda #0
+       sta logo_rise
        rts
_glint: dec l_glint_t
        bpl _out
        lda #LOGO_GLINT
        sta l_glint_t
        lda l_glint                     ; 0-4 lights a gold, then a rest until 23
        inc a
        cmp #24
        bcc +
        lda #0
+       sta l_glint
        cmp #5                          ; the entry lit this step ($ff: resting)
        bcc +
        lda #$ff - COL_LOGO0
+       clc
        adc #COL_LOGO0
        sta l_glint_entry
        ldx #4
-       lda palette_rgb+COL_LOGO0+512,x
        taz
        lda palette_rgb+COL_LOGO0+256,x
        tay
        lda palette_rgb+COL_LOGO0,x
        phx
        pha
        txa
        clc
        adc #COL_LOGO0
        tax
        pla
        cpx l_glint_entry
        bne +
        lda #255                        ; the glinting gold: white
        ldy #255
        ldz #240
+       jsr pal_set
        plx
        dex
        bpl -
        ldz #0
_out:   rts
l_glint_entry:  .byte 0

title_draw:
        lda #COL_BG
        jsr fcm_clear
        ; the logo: LOGO_COLS x LOGO_ROWS tiles, centred
        lda #0
        sta l_tt_i
        sta bs_x+1
        sta bs_y+1
-       lda l_tt_i
        ldx #0                          ; column = i mod LOGO_COLS, row = i / LOGO_COLS
        sec
_mod:   sbc #LOGO_COLS
        bcc +
        inx
        bra _mod
+       adc #LOGO_COLS
        tay
        lda l_logo_x,y
        sta bs_x
        lda l_logo_x_hi,y
        sta bs_x+1
        lda l_logo_y,x
        clc
        adc logo_rise
        sta bs_y
        lda l_tt_i
        clc
        adc #SPR_LOGO0
        sta bs_id
        jsr blit_sprite
        inc l_tt_i
        lda l_tt_i
        cmp #LOGO_COLS * LOGO_ROWS
        bne -
        lda #COL_SHADOW
        sta ftext_shadow
        lda #COL_DIM
        sta ftext_col
        lda #66
        sta ftext_y
        lda #<str_sub
        ldx #>str_sub
        jsr ftext_centre
        ; a parade of the icons: Light along the top, Dark below
        lda #0
        sta l_tt_i
-       ldx l_tt_i
        stx bs_id
        lda l_parade_x,x
        sta bs_x
        lda #0
        sta bs_x+1
        sta bs_y+1
        lda #86
        sta bs_y
        jsr blit_sprite
        lda bs_id
        clc
        adc #8
        sta bs_id
        lda #110
        sta bs_y
        jsr blit_sprite
        inc l_tt_i
        lda l_tt_i
        cmp #8
        bne -
        ; the options
        lda #COL_TEXT
        sta ftext_col
        lda #144
        sta ftext_y
        ldx opt_players
        lda l_opt_lo,x
        pha
        lda l_opt_hi,x
        tax
        pla
        jsr ftext_centre
        lda #156
        sta ftext_y
        ldx opt_first
        lda l_first_lo,x
        pha
        lda l_first_hi,x
        tax
        pla
        jsr ftext_centre
        lda #COL_LIGHT_SIDE
        sta ftext_col
        lda #176
        sta ftext_y
        lda #<str_ready
        ldx #>str_ready
        jmp ftext_centre
l_tt_i:         .byte 0
l_parade_x:     .byte 40 + range(8) * 30
l_logo_x:       .byte <((320 - LOGO_COLS * SPR_W) / 2 + range(LOGO_COLS) * SPR_W)
l_logo_x_hi:    .byte >((320 - LOGO_COLS * SPR_W) / 2 + range(LOGO_COLS) * SPR_W)
l_logo_y:       .byte 18 + range(LOGO_ROWS) * SPR_H
l_opt_lo:       .byte <str_two, <str_cpu_light, <str_cpu_dark
l_opt_hi:       .byte >str_two, >str_cpu_light, >str_cpu_dark
l_first_lo:     .byte <str_light_first, <str_dark_first
l_first_hi:     .byte >str_light_first, >str_dark_first

str_sub:        .null "THE LIGHT AND THE DARK"
str_two:        .null "F3: TWO PLAYERS"
str_cpu_light:  .null "F3: COMPUTER PLAYS LIGHT"
str_cpu_dark:   .null "F3: COMPUTER PLAYS DARK"
str_light_first: .null "F5: LIGHT MOVES FIRST"
str_dark_first: .null "F5: DARK MOVES FIRST"
str_ready:      .null "PRESS F7 OR FIRE WHEN READY"

; the result over the board, then back to the title
game_over:
        lda #SCENE_BOARD
        sta scene
        ldx game_result
        lda l_result_msg,x
        sta view_msg
        lda #$3f                        ; THE GAME IS ENDED...
        sta view_msg2
        jsr music_end
        lda #<OVER_FRAMES
        sta l_go_t
        lda #>OVER_FRAMES
        sta l_go_t+1
-       jsr frame
        lda joy_new
        and #JOY_FIRE
        bne +
        lda l_go_t
        bne _dec
        dec l_go_t+1
_dec:   dec l_go_t
        lda l_go_t
        ora l_go_t+1
        bne -
+       lda #NO_SLOT
        sta view_msg
        sta view_msg2
        rts
l_result_msg:   .byte NO_SLOT, $06, $07, $08, $40
l_go_t:         .word 0
