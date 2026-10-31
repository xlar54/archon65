;=======================================================================================
; fx.asm - spell effects as VIC-IV hardware sprites over the board.
;
; An effect is an animation of 32 x 32 frames (src/assets/effects, built into
; gen/effects.asm): two 16-colour sprites side by side, 15 colours of its own. Up to
; FX_SLOTS play at once, each on its own pair of sprites; they can drift along a curve.
; They show on the board only: any other scene stops them.
;
;   fx_init        sprites ready (after gfx_init)
;   fx_square      A = square -> fx_x / fx_y: an effect standing on that square
;   fx_start       A = effect at fx_x / fx_y (fx_flags: FXF_BACKWARDS, FXF_LOOP) ->
;                  X = its slot, carry set if every slot is busy
;   fx_fly         X = slot: fly it to fx_x / fx_y in FX_FLY_FRAMES along an arc;
;                  a looping effect ends when it lands
;   fx_on / fx_on_wait   A = effect, X = square: start it there / and wait for the end
;   fx_wait        run frames until every effect has ended
;   fx_update      once a frame (from main.asm frame)
;   fx_pulse       Shift Time: the board's palette dims and comes back
;   fx_summon_burst  the summoned elemental (last_elem) bursts into being where it is
;                  held (held_x / held_y), and the burst plays out
;
; Test: poke dbg_fx_sq = square, dbg_fx_flags, then dbg_fx = effect + 1.
; dbg_fx_runs counts each effect's starts.
;=======================================================================================

FX_BASE         = $12000                ; the frames in chip RAM (bank 1, free after boot)
FX_SLOTS        = 4                     ; sprites 2n, 2n+1
FX_H            = 32
FX_FLY_FRAMES   = 32                    ; a flight (a power of 2: fx_fly divides by shifting)
FX_LIFT         = $0180                 ; a flight starts rising 1.5 px a frame (8.8) ...
FX_GRAVITY      = $18                   ; ... and falls back 3/32 px a frame: a 12 px arc
FX_SPR_PAL_BANK = 1                     ; the sprites' own palette bank
FXF_BACKWARDS   = 1
FXF_LOOP        = 2

        .cerror FX_BASE + FX_BYTES > $1f800, "effect frames reach colour RAM at $1F800"

fx_x:           .word 0                 ; screen position of an effect's top-left
fx_y:           .byte 0
fx_flags:       .byte 0                 ; for the next fx_start
dbg_fx:         .byte 0
dbg_fx_sq:      .byte 40
dbg_fx_flags:   .byte 0
dbg_fx_runs:    .fill FX_COUNT

fxs_anim:       .fill FX_SLOTS, $ff     ; effect, $ff = slot free
fxs_flags:      .fill FX_SLOTS
fxs_frame:      .fill FX_SLOTS
fxs_wait:       .fill FX_SLOTS          ; game frames until the next animation frame
fxs_xf:         .fill FX_SLOTS          ; x, 8.8 (fraction, low, high)
fxs_xl:         .fill FX_SLOTS
fxs_xh:         .fill FX_SLOTS
fxs_yf:         .fill FX_SLOTS          ; y, 8.8
fxs_y:          .fill FX_SLOTS
fxs_vxf:        .fill FX_SLOTS          ; velocity, 8.8 signed
fxs_vx:         .fill FX_SLOTS
fxs_vyf:        .fill FX_SLOTS
fxs_vy:         .fill FX_SLOTS
fxs_moves:      .fill FX_SLOTS          ; frames of flight left

fx_init:
        jsr hws_init
        ldx #7
-       jsr hws_full_colour
        lda #FX_H
        jsr hws_height
        dex
        bpl -
        lda #FX_SPR_PAL_BANK
        jsr hws_pal_bank
        ; the frames: attic -> chip RAM
        lda #<ATTIC_EFFECTS
        sta ptr1
        lda #>ATTIC_EFFECTS
        sta ptr1+1
        lda #`ATTIC_EFFECTS
        sta ptr1+2
        lda #ATTIC_EFFECTS >> 24
        sta ptr1+3
        lda #<FX_BASE
        sta ptr2
        lda #>FX_BASE
        sta ptr2+1
        lda #`FX_BASE
        sta ptr2+2
        lda #0
        sta ptr2+3
        lda #<FX_BYTES
        sta tmp5
        lda #>FX_BYTES
        sta tmp5+1
        jmp dma_copy_far

; A = square -> fx_x / fx_y: the frame's bottom on the square's bottom, centred
fx_square:
        jsr sq_xy
        sec
        lda box_x
        sbc #(FX_H - SQ_W) / 2
        sta fx_x
        lda box_x+1
        sbc #0
        sta fx_x+1
        lda box_y
        sec
        sbc #FX_H - SQ_H
        sta fx_y
        rts

fx_on:
        pha
        txa
        jsr fx_square
        pla
        jmp fx_start

fx_on_wait:
        jsr fx_on
fx_wait:
-       jsr fx_busy
        bcc +
        jsr frame
        bra -
+       rts

; carry set while an effect plays
fx_busy:
        ldx #FX_SLOTS - 1
-       lda fxs_anim,x
        bpl +
        dex
        bpl -
        clc
        rts
+       sec
        rts

fx_start:
        sta tmp2
        ldx #0
-       lda fxs_anim,x
        bmi _free
        inx
        cpx #FX_SLOTS
        bne -
        sec
        rts
_free:  lda tmp2
        sta fxs_anim,x
        tay
        lda dbg_fx_runs,y
        inc a
        sta dbg_fx_runs,y
        lda fx_flags
        sta fxs_flags,x
        lda #0
        sta fx_flags
        sta fxs_moves,x
        sta fxs_xf,x
        sta fxs_yf,x
        lda fx_x
        sta fxs_xl,x
        lda fx_x+1
        sta fxs_xh,x
        lda fx_y
        sta fxs_y,x
        lda fx_delay,y
        sta fxs_wait,x
        lda #0
        sta tmp3
        lda fxs_flags,x                 ; backwards: from the last frame
        and #FXF_BACKWARDS
        beq +
        lda fx_frames,y
        dec a
        sta tmp3
+       lda tmp3
        sta fxs_frame,x
        jsr l_fx_palette
        jsr l_fx_show
        clc
        rts

; X = slot: aim it at fx_x / fx_y. v = d / FX_FLY_FRAMES (d * 8 in 8.8), then lifted
fx_fly:
        lda #FX_FLY_FRAMES
        sta fxs_moves,x
        sec                             ; vx = (fx_x - x) * 8
        lda fx_x
        sbc fxs_xl,x
        sta tmp0
        lda fx_x+1
        sbc fxs_xh,x
        sta tmp0+1
        jsr l_fx_times8
        lda tmp0
        sta fxs_vxf,x
        lda tmp0+1
        sta fxs_vx,x
        sec                             ; vy = (fx_y - y) * 8 - FX_LIFT
        lda fx_y
        sbc fxs_y,x
        sta tmp0
        lda #0
        sbc #0
        sta tmp0+1
        jsr l_fx_times8
        sec
        lda tmp0
        sbc #<FX_LIFT
        sta fxs_vyf,x
        lda tmp0+1
        sbc #>FX_LIFT
        sta fxs_vy,x
        rts
l_fx_times8:
        asl tmp0
        rol tmp0+1
        asl tmp0
        rol tmp0+1
        asl tmp0
        rol tmp0+1
        rts

fx_update:
        lda scene
        cmp #SCENE_BOARD
        beq +
        jmp fx_stop
+       lda dbg_fx
        beq _slots
        dec a
        pha
        lda #0
        sta dbg_fx
        lda dbg_fx_flags
        sta fx_flags
        ldx dbg_fx_sq
        pla
        jsr fx_on
_slots: ldx #FX_SLOTS - 1
_slot:  lda fxs_anim,x
        bmi _next
        jsr l_fx_move
        bcs _end
        jsr l_fx_animate
        bcs _end
        jsr l_fx_show
        bra _next
_end:   jsr l_fx_off
_next:  dex
        bpl _slot
        rts

fx_stop:
        ldx #FX_SLOTS - 1
-       lda fxs_anim,x
        bmi +
        jsr l_fx_off
+       dex
        bpl -
        rts

; X = slot: one frame of flight. Carry set when a looping effect has landed.
l_fx_move:
        lda fxs_moves,x
        beq _still
        clc
        lda fxs_xf,x
        adc fxs_vxf,x
        sta fxs_xf,x
        lda fxs_xl,x
        adc fxs_vx,x
        sta fxs_xl,x
        lda fxs_vx,x                    ; sign-extend into the high byte
        and #$80
        beq +
        lda #$ff
+       adc fxs_xh,x
        sta fxs_xh,x
        clc
        lda fxs_yf,x
        adc fxs_vyf,x
        sta fxs_yf,x
        lda fxs_y,x
        adc fxs_vy,x
        sta fxs_y,x
        clc                             ; it falls back
        lda fxs_vyf,x
        adc #FX_GRAVITY
        sta fxs_vyf,x
        lda fxs_vy,x
        adc #0
        sta fxs_vy,x
        dec fxs_moves,x
        bne _still
        lda fxs_flags,x
        and #FXF_LOOP
        beq _still
        sec
        rts
_still: clc
        rts

; X = slot: the animation clock. Carry set when a one-shot effect has finished.
l_fx_animate:
        dec fxs_wait,x
        bne _same
        ldy fxs_anim,x
        lda fx_delay,y
        sta fxs_wait,x
        lda fxs_flags,x
        and #FXF_BACKWARDS
        bne _back
        inc fxs_frame,x
        lda fxs_frame,x
        cmp fx_frames,y
        bne _same
        lda fxs_flags,x
        and #FXF_LOOP
        beq _done
        lda #0
        sta fxs_frame,x
        bra _same
_back:  lda fxs_frame,x
        bne +
        lda fxs_flags,x
        and #FXF_LOOP
        beq _done
        lda fx_frames,y
+       dec a
        sta fxs_frame,x
_same:  clc
        rts
_done:  sec
        rts

; X = slot: its two sprites at its position, showing its frame
l_fx_show:
        stx tmp7
        ldy fxs_anim,x                  ; pointer = (FX_BASE + frame * 512) / 64
        lda fx_first,y
        clc
        adc fxs_frame,x
        sta tmp6
        lda #0
        sta tmp6+1
        ldy #3                          ; * 8
-       asl tmp6
        rol tmp6+1
        dey
        bne -
        clc
        lda tmp6
        adc #<(FX_BASE / 64)
        sta tmp6
        lda tmp6+1
        adc #>(FX_BASE / 64)
        sta tmp6+1
        txa                             ; sprites 2n, 2n+1: hws_ptrs + 4n
        asl
        asl
        tay
        lda tmp6
        sta hws_ptrs,y
        lda tmp6+1
        sta hws_ptrs+1,y
        clc                             ; the right half follows the left (256 bytes)
        lda tmp6
        adc #4
        sta hws_ptrs+2,y
        lda tmp6+1
        adc #0
        sta hws_ptrs+3,y
        lda fxs_xl,x
        sta hws_x
        lda fxs_xh,x
        sta hws_x+1
        lda fxs_y,x
        sta hws_y
        lda #0
        sta hws_y+1
        txa
        asl
        tax
        jsr hws_place
        jsr hws_on
        clc
        lda hws_x
        adc #16
        sta hws_x
        bcc +
        inc hws_x+1
+       inx
        jsr hws_place
        jsr hws_on
        ldx tmp7
        rts

; X = slot: off
l_fx_off:
        lda #$ff
        sta fxs_anim,x
        txa
        asl
        tax
        jsr hws_off
        inx
        jsr hws_off
        txa
        lsr
        tax
        rts

; X = slot: its effect's 15 colours into its sprites' palette entries
l_fx_palette:
        stx tmp7
        lda #FX_SPR_PAL_BANK
        jsr hws_pal_edit
        lda fxs_anim,x                  ; source: effect * 16
        asl
        asl
        asl
        asl
        tay
        txa                             ; destination: sprite 2n * 16 = n * 32
        asl
        asl
        asl
        asl
        asl
        tax
        lda #16
        sta tmp2
-       lda fx_pal_r,y
        sta $d100,x
        sta $d110,x
        lda fx_pal_g,y
        sta $d200,x
        sta $d210,x
        lda fx_pal_b,y
        sta $d300,x
        sta $d310,x
        iny
        inx
        dec tmp2
        bne -
        lda hws_screen_bank
        jsr hws_pal_edit
        ldx tmp7
        rts

fx_summon_burst:
        sec
        lda held_x
        sbc #(FX_H - SQ_W) / 2
        sta fx_x
        lda held_x+1
        sbc #0
        sta fx_x+1
        lda held_y
        sec
        sbc #FX_H - SQ_H
        sta fx_y
        lda #FX_SUMMON_AIR              ; the four bursts are in elemental order
        clc
        adc last_elem
        jsr fx_start
        jmp fx_wait

; Shift Time: the board dims and comes back while the flow of time turns
FX_PULSE_LOW    = 90
FX_PULSE_STEP   = 11
fx_pulse:
        lda #255
-       sec
        sbc #FX_PULSE_STEP
        cmp #FX_PULSE_LOW
        bcc +
        pha
        jsr pal_set_level
        jsr frame
        pla
        bra -
+       lda #FX_PULSE_LOW
-       clc
        adc #FX_PULSE_STEP
        bcs +
        pha
        jsr pal_set_level
        jsr frame
        pla
        bra -
+       lda #255
        jmp pal_set_level
