;=======================================================================================
; sound.asm - sound effects and music.
;
; Effects: SID 1 voice 1 belongs to Light, voice 2 to Dark. Each plays one effect stream
; (src/assets/sound.asm) at a time, by priority: walking $80 < ready bell $81 < attack $82
; < hit $83. Voice 3 runs noise, silent, for the hit sound's sync (as the original).
; Music: SID 2, three voices of note lists.
;
;   sound_init     SIDs ready, the frame hook installed (sound_irq, with fcm_irq)
;   sound_ready / sound_attack / sound_hit / sound_death   X = fighter (= voice)
;   sound_walk / sound_walk_stop   X = fighter (walking loop, its type's sound)
;   sound_attack_end  X = fighter: cut its attack sound
;   sound_zoom     the rising combat-zoom tone       sound_turn   A = side: the turn bell
;   sound_off      both effect voices silent
;   music_title / music_end / music_stop
;=======================================================================================

SID2            = $D420
PRIO_WALK       = $80
PRIO_BELL       = $81
PRIO_ATTACK     = $82
PRIO_HIT        = $83

snd_prio:       .fill 2                 ; 0 = idle
snd_count:      .fill 2
snd_ptr_lo:     .fill 2
snd_ptr_hi:     .fill 2
snd_sweep:      .byte 0                 ; zoom: frames left of the rising tone
snd_sweep_hi:   .byte 0
l_voice_reg:    .byte 0, 7              ; SID 1 voice offsets

sound_init:
        ldx #$18
        lda #0
-       sta SID1,x
        sta SID2,x
        dex
        bpl -
        lda #$08                        ; pulse width 50 %, voices 1 and 2
        sta SID1+3
        sta SID1+10
        lda #$40                        ; voice 3: noise at $0A40, gated, not heard
        sta SID1+14
        lda #$0a
        sta SID1+15
        lda #$81
        sta SID1+18
        lda #$8f                        ; volume 15, voice 3 off
        sta SID1+$18
        lda #$0f
        sta SID2+$18
        lda #0
        sta snd_prio
        sta snd_prio+1
        sta snd_sweep
        sta music_on
        lda #<sound_irq
        sta irq_hook
        lda #>sound_irq
        sta irq_hook+1
        rts

; the frame hook: buffer flips, effects, music
sound_irq:
        jsr fcm_irq
        ldx #1
-       jsr l_snd_voice
        dex
        bpl -
        jsr l_snd_sweep
        jmp music_frame

; A = stream, Y = priority, X = voice: start it if it outranks what is playing
l_snd_start:
        sta l_ss_stream
        tya
        cmp snd_prio,x
        bcc +
        php
        sei
        sta snd_prio,x
        ldy l_ss_stream
        lda snd_lo,y
        sta snd_ptr_lo,x
        lda snd_hi,y
        sta snd_ptr_hi,x
        lda #0
        sta snd_count,x
        plp
+       rts
l_ss_stream:    .byte 0

sound_ready:
        lda #SND_BELL
        cpx #SIDE_DARK
        bne +
        lda #SND_BELL_DARK
+       ldy #PRIO_BELL
        jmp l_snd_start

sound_attack:
        ldy f_type,x
        lda type_attack_snd,y
        ldy #PRIO_ATTACK
        jmp l_snd_start

sound_death:
sound_hit:
        lda #SND_HIT
        cpx #SIDE_DARK
        bne +
        lda #SND_HIT_DARK
+       ldy #PRIO_HIT
        jmp l_snd_start

sound_walk:
        lda f_type,x
; A = icon type, X = voice: its walking loop, only on a quiet voice
sound_walk_type:
        tay
        lda snd_prio,x
        bne +
        tya
        sta snd_type,x                  ; (the loop ($FE) comes back to this type)
        lda type_walk_snd,y
        ldy #PRIO_WALK
        jmp l_snd_start
+       rts
snd_type:       .fill 2

sound_walk_stop:
        lda #PRIO_WALK
        bra l_snd_cut
sound_attack_end:
        lda #PRIO_ATTACK
; A = priority: stop voice X if that is what it plays
l_snd_cut:
        cmp snd_prio,x
        bne +
        lda #0
        sta snd_prio,x
        ldy l_voice_reg,x
        sta SID1+4,y
+       rts

sound_off:
        ldx #1
-       lda #0
        sta snd_prio,x
        ldy l_voice_reg,x
        sta SID1+4,y
        dex
        bpl -
        sta snd_sweep
        rts

; A = side: the bell that starts a board turn, on voice 1
sound_turn:
        ldx #0
        tay
        lda #SND_BELL
        cpy #SIDE_DARK
        bne +
        lda #SND_BELL_DARK
+       ldy #PRIO_HIT
        jmp l_snd_start

; the zoom: a triangle re-attacked every 4 frames, 2 steps higher each time
sound_zoom:
        ldx #0
        lda #SND_ZOOM
        ldy #PRIO_HIT
        jsr l_snd_start
        lda #$23
        sta snd_sweep_hi
        lda #ZOOM_STEPS * 4
        sta snd_sweep
        rts
l_snd_sweep:
        lda snd_sweep
        beq +
        dec snd_sweep
        and #3
        bne +
        lda #0
        sta SID1+4
        lda snd_sweep_hi
        clc
        adc #2
        sta snd_sweep_hi
        sta SID1+1
        lda #$11
        sta SID1+4
+       rts

; X = voice: one frame of its effect stream
l_snd_voice:
        lda snd_prio,x
        beq _out
        lda snd_count,x
        beq _read
        dec snd_count,x
        bne _out
_read:  lda snd_ptr_lo,x
        sta l_sv_ptr
        lda snd_ptr_hi,x
        sta l_sv_ptr+1
        ldy l_voice_reg,x
_byte:  jsr l_sv_get
        cmp #$fe
        beq _loop
        cmp #$ff
        beq _end
        cmp #0
        bne _step
        sta SID1+4,y                    ; gate off, then on with the next step
        bra _byte
_loop:  ldy snd_type,x                   ; back to the walker's sound
        lda type_walk_snd,y
        tay
        lda snd_lo,y
        sta l_sv_ptr
        lda snd_hi,y
        sta l_sv_ptr+1
        ldy l_voice_reg,x
        bra _byte
_end:   lda #0
        sta SID1+4,y
        sta snd_prio,x
        sta snd_count,x
_out:   rts
_step:  sta snd_count,x
        jsr l_sv_get
        sta SID1+5,y                    ; AD
        jsr l_sv_get
        sta SID1+6,y                    ; SR
        jsr l_sv_get
        sta SID1+0,y                    ; frequency
        jsr l_sv_get
        sta SID1+1,y
        jsr l_sv_get
        sta SID1+4,y                    ; control
        lda l_sv_ptr
        sta snd_ptr_lo,x
        lda l_sv_ptr+1
        sta snd_ptr_hi,x
        rts
; the next byte at l_sv_ptr (keeps X, Y)
l_sv_get:
        phy
        ldy #0
        lda (l_sv_ptr),y
        ply
        inw l_sv_ptr
        rts

;---------------------------------------------------------------------------------------
; music: per voice a list of notes DUR, FREQHI (0 = rest), FREQLO, GATE; DUR 0 ends
music_on:       .byte 0
mus_ptr_lo:     .fill 3
mus_ptr_hi:     .fill 3
mus_count:      .fill 3
mus_gate:       .fill 3
mus_wave:       .fill 3
l_mus_reg:      .byte 0, 7, 14

music_title:
        lda #<song_title_v0
        ldx #>song_title_v0
        ldy #0
        jsr l_mus_voice
        lda #<song_title_v1
        ldx #>song_title_v1
        ldy #1
        jsr l_mus_voice
        lda #<song_title_v2
        ldx #>song_title_v2
        ldy #2
        jsr l_mus_voice
        ldx #2
-       lda song_title_ad,x
        ldy l_mus_reg,x
        sta SID2+5,y
        lda song_title_sr,x
        sta SID2+6,y
        lda song_title_wave,x
        sta mus_wave,x
        dex
        bpl -
        lda #1
        sta music_on
        rts

music_end:
        lda #<song_end_v0
        ldx #>song_end_v0
        ldy #0
        jsr l_mus_voice
        lda #<song_end_v1
        ldx #>song_end_v1
        ldy #1
        jsr l_mus_voice
        lda #<song_end_v2
        ldx #>song_end_v2
        ldy #2
        jsr l_mus_voice
        ldx #2
-       lda song_end_ad,x
        ldy l_mus_reg,x
        sta SID2+5,y
        lda song_end_sr,x
        sta SID2+6,y
        lda song_end_wave,x
        sta mus_wave,x
        dex
        bpl -
        lda #1
        sta music_on
        rts

; A/X = note list, Y = voice
l_mus_voice:
        sta mus_ptr_lo,y
        txa
        sta mus_ptr_hi,y
        lda #1
        sta mus_count,y
        lda #0
        sta mus_gate,y
        rts

music_stop:
        lda #0
        sta music_on
        sta SID2+4
        sta SID2+11
        sta SID2+18
        rts

music_frame:
        lda music_on
        beq _out
        ldx #2
_v:     ldy l_mus_reg,x
        lda mus_gate,x                  ; release the gate after GATE frames
        beq +
        dec mus_gate,x
        bne +
        lda mus_wave,x
        and #$fe
        sta SID2+4,y
+       lda mus_count,x
        beq _next                       ; this voice has ended
        dec mus_count,x
        bne _next
        lda mus_ptr_lo,x                ; the next note
        sta l_sv_ptr
        lda mus_ptr_hi,x
        sta l_sv_ptr+1
        jsr l_sv_get
        sta mus_count,x
        beq _stop
        jsr l_sv_get
        sta tmp_mus
        jsr l_sv_get
        sta SID2+0,y
        lda mus_wave,x
        and #$fe
        sta SID2+4,y
        lda tmp_mus
        beq _rest
        sta SID2+1,y
        lda mus_wave,x
        sta SID2+4,y
_rest:  jsr l_sv_get
        sta mus_gate,x
        lda tmp_mus
        bne +
        lda #0
        sta mus_gate,x
+       lda l_sv_ptr
        sta mus_ptr_lo,x
        lda l_sv_ptr+1
        sta mus_ptr_hi,x
_next:  dex
        bpl _v
        ; all three ended: the song is over
        lda mus_count
        ora mus_count+1
        ora mus_count+2
        bne _out
        sta music_on
_out:   rts
_stop:  lda #0
        sta SID2+4,y
        bra _next
tmp_mus:        .byte 0

; true when a song is still playing
music_playing:
        lda music_on
        rts
