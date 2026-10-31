;=======================================================================================
; lib/sid.asm - simple SID sound effects. One voice per effect class;
; each effect is a waveform, start pitch, per-frame pitch slide, length and envelope.
;
;   sid_init       SID 1 silent, full volume
;   sfx_play       A = effect number (index into the sfx_* tables)
;   sfx_frame      call once a frame (from the IRQ hook)
;
; Edit the tables for your game (or define SFX_TABLES_OWN = 1 and supply your own
; sfx_voice .. sfx_sr with SFX_COUNT entries).
;=======================================================================================

        .weak
SFX_TABLES_OWN  = 0
        .endweak

        .if !SFX_TABLES_OWN
SFX_SHOT        = 0
SFX_EXPLODE     = 1
SFX_BIGBOOM     = 2
SFX_PICKUP      = 3
SFX_HIT         = 4
SFX_CHARGE      = 5
SFX_DIE         = 6
;               shot  expl  big   pick  hit   charge die
sfx_voice:  .byte 0,    7,    7,    14,   14,   0,     7     ; voice register offset
sfx_wave:   .byte $41,  $81,  $81,  $11,  $21,  $41,   $81   ; waveform + gate
sfx_fhi:    .byte $30,  $10,  $08,  $20,  $40,  $08,   $0c   ; start pitch (high byte)
sfx_fstep:  .byte $fd,  $ff,  $00,  $02,  $f8,  $01,   $ff   ; signed slide per frame
sfx_len:    .byte 6,    20,   40,   16,   4,    30,    50    ; frames
sfx_ad:     .byte $08,  $09,  $0b,  $08,  $00,  $0a,   $0c
sfx_sr:     .byte $80,  $f9,  $fb,  $a8,  $a0,  $a8,   $fc
        .endif

l_sfx_timer: .fill 3
l_sfx_cur:   .fill 3
l_sfx_freq:  .fill 3
l_sfx_vidx:  .byte 0,0,0,0,0,0,0,1,0,0,0,0,0,0,2
l_sfx_voffs: .byte 0, 7, 14

sid_init:
        ldx #$18
        lda #0
-       sta SID1,x
        dex
        bpl -
        lda #$0f
        sta SID1+$18
        rts

sfx_play:
        tay
        ldx sfx_voice,y
        lda l_sfx_vidx,x
        tax
        tya
        sta l_sfx_cur,x
        lda sfx_len,y
        sta l_sfx_timer,x
        lda sfx_fhi,y
        sta l_sfx_freq,x
        ldx sfx_voice,y
        lda #0
        sta SID1+4,x                    ; gate off to retrigger
        sta SID1,x
        sta SID1+2,x
        lda sfx_fhi,y
        sta SID1+1,x
        lda #$08
        sta SID1+3,x                    ; pulse width
        lda sfx_ad,y
        sta SID1+5,x
        lda sfx_sr,y
        sta SID1+6,x
        lda sfx_wave,y
        sta SID1+4,x
        rts

sfx_frame:
        ldx #0
l_sf_v:
        lda l_sfx_timer,x
        beq l_sf_next
        dec l_sfx_timer,x
        ldy l_sfx_cur,x
        lda l_sfx_voffs,x
        taz
        lda l_sfx_timer,x
        bne +
        phx                             ; release
        tza
        tax
        lda sfx_wave,y
        and #$fe
        sta SID1+4,x
        plx
        bra l_sf_next
+       clc
        lda l_sfx_freq,x
        adc sfx_fstep,y
        sta l_sfx_freq,x
        phx
        pha
        tza
        tax
        pla
        sta SID1+1,x
        plx
l_sf_next:
        inx
        cpx #3
        bne l_sf_v
        rts
