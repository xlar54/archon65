;=======================================================================================
; spells.asm - the mages' seven spells.
;
;   cast_spell     the human side's spell menu and the chosen spell. Carry set when the
;                  turn must start again (Cease Conjuring, or no spells left).
;   spell_<name>   the effects, shared with the computer player (ai.asm): arguments in
;                  sp_a / sp_b (squares) as noted
;   spell_ok_target  A = square -> carry clear when magic may touch it (not a power
;                  point); shows the refusal otherwise
;
; A spell counts once it has worked: spell_used marks it, spells_cast counts it (the
; combat penalty on the home power point, game.asm).
;=======================================================================================

SP_TELEPORT     = 0
SP_HEAL         = 1
SP_SHIFT        = 2
SP_EXCHANGE     = 3
SP_SUMMON       = 4
SP_REVIVE       = 5
SP_IMPRISON     = 6
SP_CEASE        = 7

MSG_SPELL_NAME  = $2c                   ; + spell
MSG_FRAMES      = 75                    ; how long a passing message stays

sp_a:           .byte 0
sp_b:           .byte 0
sp_choice:      .byte 0
mage_sq:        .byte 0

;---------------------------------------------------------------------------------------
; mage_sq = the casting mage's square (set by the caller)
cast_spell:
        jsr spells_left
        bne _menu
        lda #$00                        ; OH, WOE! YOUR SPELLS ARE GONE!
        jsr show_message
        sec
        rts
_menu:  lda #SP_CEASE
        sta sp_choice
        jsr next_spell                  ; start on the first available spell
_show:  lda #$36                        ; SELECT A SPELL
        sta view_msg
        lda sp_choice
        clc
        adc #MSG_SPELL_NAME
        sta view_msg2
        jsr frame
        lda game_result
        bne _cease
        ldx side
        jsr board_stick
        bcs _fire
        sta tmp3
        and #JOY_DOWN | JOY_RIGHT
        beq +
        jsr next_spell
        bra _show
+       lda tmp3
        and #JOY_UP | JOY_LEFT
        beq _show
        jsr prev_spell
        bra _show
_fire:  lda sp_choice
        cmp #SP_CEASE
        beq _cease
        lda #NO_SLOT                    ; (the spell's name off the second line)
        sta view_msg2
        jsr human_spell
        bcs _show                       ; refused: choose again
        ldx side                        ; it worked
        lda side
        asl
        asl
        asl
        sec
        sbc side                        ; side * 7
        clc
        adc sp_choice
        tay
        lda #1
        sta spell_used,y
        inc spells_cast,x
        lda #$05                        ; IT IS DONE
        jsr show_message
        clc
        rts
_cease: lda #$3e                        ; SPELL IS CANCELED. CHOOSE ANOTHER
        jsr show_message
        sec
        rts

; A != 0 when the side has an unused spell
spells_left:
        jsr l_spell_base
        ldy #NSPELLS
-       lda spell_used,x
        beq +
        inx
        dey
        bne -
        lda #0
        rts
+       lda #1
        rts
; X = side * 7
l_spell_base:
        lda side
        asl
        asl
        asl
        sec
        sbc side
        tax
        rts

; sp_choice -> the next spell still available (Cease Conjuring always is)
next_spell:
        lda sp_choice
        inc a
        cmp #SP_CEASE + 1
        bcc +
        lda #0
+       sta sp_choice
        jsr l_available
        bne next_spell
        rts
prev_spell:
        lda sp_choice
        dec a
        bpl +
        lda #SP_CEASE
+       sta sp_choice
        jsr l_available
        bne prev_spell
        rts
; A = 0 when sp_choice is available
l_available:
        lda sp_choice
        cmp #SP_CEASE
        beq +
        jsr l_spell_base
        txa
        clc
        adc sp_choice
        tax
        lda spell_used,x
        rts
+       lda #0
        rts

; show message A for a moment (blocks, the board keeps animating)
show_message:
        sta view_msg
        lda #NO_SLOT
        sta view_msg2
        lda #MSG_FRAMES
        sta l_sm_t
-       jsr frame
        dec l_sm_t
        bne -
        lda #NO_SLOT
        sta view_msg
        rts
l_sm_t:         .byte 0

; A = message: show it as the second line while the player keeps choosing
note_message:
        sta view_msg2
        rts

;---------------------------------------------------------------------------------------
; human_spell - the human's targets for sp_choice, then the effect. Carry set = refused.
human_spell:
        lda sp_choice
        asl
        tax
        jmp (l_hs_table,x)
l_hs_table:     .word hs_teleport, hs_heal, hs_shift, hs_exchange, hs_summon, hs_revive
                .word hs_imprison

; select_square - a free frame, from where it is (or the mage); A = prompt. Returns
; A = square on fire, carry set if the game was quit.
select_square:
        sta view_msg                    ; (a refusal note in view_msg2 stays until a move)
        lda cursor_sq
        cmp #NO_SLOT
        bne _frame
        lda mage_sq
        sta cursor_sq
_frame: jsr frame
        lda game_result
        bne _quit
        ldx side
        jsr board_stick
        php
        beq +
        tax
        lda cursor_sq
        jsr sq_step
        sta cursor_sq
        lda #NO_SLOT
        sta view_msg2
+       plp
        bcc _frame
        lda cursor_sq
        clc
        rts
_quit:  sec
        rts

; A = square -> carry set (refused, message shown) when it is a power point
spell_ok_target:
        jsr is_power_point
        bcc +
        lda #$34                        ; POWER POINTS ARE PROOF AGAINST MAGIC
        jsr note_message
        sec
+       rts

; A = square -> carry clear when it holds an icon of `side` (X = slot)
own_icon_at:
        tax
        lda board,x
        bmi _no
        tax
        jsr slot_side
        cmp side
        bne _no
        clc
        rts
_no:    sec
        rts

; A = square -> carry clear when it holds an enemy icon (X = slot)
enemy_at:
        tax
        lda board,x
        bmi _no
        tax
        jsr slot_side
        cmp side
        beq _no
        clc
        rts
_no:    sec
        rts

; X = slot -> carry set when either side has it imprisoned
is_prisoner:
        cpx prisoner
        beq +
        cpx prisoner+1
        beq +
        clc
        rts
+       sec
        rts

;---------------------------------------------------------------------------------------
hs_teleport:
        lda #$0b                        ; WHICH ICON WILL YOU TELEPORT?
_pick:  jsr select_square
        bcs _quit
        sta sp_a
        jsr own_icon_at
        bcs _again
        jsr is_prisoner
        bcc +
        lda #$14                        ; ALAS, THIS ICON IS IMPRISONED
        jsr note_message
        bra _again
+       lda sp_a
        jsr spell_ok_target
        bcs _again
        lda #$0c                        ; WHERE WILL YOU TELEPORT IT?
        sta view_msg
        ldx sp_a
        jmp spell_teleport
_again: lda #$0b
        bra _pick
_quit:  clc
        rts

hs_heal:
        lda #$0a                        ; WHICH ICON WILL YOU HEAL?
-       jsr select_square
        bcs _quit
        sta sp_a
        jsr own_icon_at
        bcs _again
        lda sp_a
        jsr spell_ok_target
        bcs _again
        jmp spell_heal
_again: lda #$0a
        bra -
_quit:  clc
        rts

hs_shift:
        jsr spell_shift
        lda #$09                        ; THE FLOW OF TIME IS REVERSED
        jsr show_message
        clc
        rts

hs_exchange:
        lda #$0d                        ; CHOOSE AN ICON TO TRANSPOSE
-       jsr select_square
        bcs _quit
        sta sp_a
        jsr l_exchangeable
        bcs _again1
        lda #$0e                        ; EXCHANGE IT WITH WHICH ICON?
_two:   jsr select_square
        bcs _quit
        sta sp_b
        cmp sp_a
        beq _again2
        jsr l_exchangeable
        bcs _again2
        jmp spell_exchange
_again1: lda #$0d
        bra -
_again2: lda #$0e
        bra _two
_quit:  clc
        rts
; A = square -> carry clear when it can be exchanged
l_exchangeable:
        pha
        tax
        lda board,x
        bmi _no
        tax
        jsr is_prisoner
        bcc +
        lda #$14                        ; ALAS, THIS ICON IS IMPRISONED
        jsr note_message
_no:    pla
        sec
        rts
+       pla
        jmp spell_ok_target

hs_summon:
        jsr summon_possible
        bcc +
        lda #$34                        ; POWER POINTS ARE PROOF AGAINST MAGIC
        jsr show_message
        sec
        rts
+       jsr summon_choose
        lda #$19                        ; SEND IT TO THE TARGET
        sta view_msg
        lda #NO_SLOT
        sta view_msg2
        jmp spell_summon_move

hs_revive:
        jsr revive_check
        bcc +
        rts                             ; the refusal was shown
+       lda #0
        sta panel_sel
        lda #$0f                        ; WHAT ICON WILL YOU REVIVE?
        sta view_msg
_list:  jsr frame
        lda game_result
        bne _quit
        ldx side
        jsr board_stick
        bcs _chosen
        sta tmp3
        and #JOY_DOWN
        beq +
        ldx panel_sel                   ; down the list, if there is more
        lda panel_list+1,x
        bmi _list
        inc panel_sel
        bra _list
+       lda tmp3
        and #JOY_UP
        beq _list
        lda panel_sel
        beq _list
        dec panel_sel
        bra _list
_chosen:
        lda #$10                        ; PLACE IT WITHIN THE CHARMED SQUARE
-       jsr select_square
        bcs _quit
        sta sp_b
        jsr in_charmed
        bcs _again
        ldx sp_b
        lda board,x
        bpl _again
        lda sp_b
        jsr spell_ok_target
        bcs _again
        ldx panel_sel
        lda panel_list,x
        sta sp_a
        jsr spell_revive
        lda #$ff
        sta panel_list
        clc
        rts
_again: lda #$10
        bra -
_quit:  lda #$ff
        sta panel_list
        clc
        rts

hs_imprison:
        jsr imprison_possible
        bcc +
        lda #$35                        ; THAT SPELL WOULD BE WASTED AT THIS TIME
        jsr show_message
        sec
        rts
+       lda #$11                        ; WHICH FOE WILL YOU IMPRISON?
-       jsr select_square
        bcs _quit
        sta sp_a
        jsr enemy_at
        bcs _again
        lda sp_a
        jsr spell_ok_target
        bcs _again
        jmp spell_imprison
_again: lda #$11
        bra -
_quit:  clc
        rts

;=======================================================================================
; Effects (also used by the computer player)
;=======================================================================================

; X = square of the icon: move it with teleport range and no power points; an enemy on
; the destination means combat. Human: the player steers; the AI sets ai_dest first.
spell_teleport:
        stx origin_sq
        lda #FX_TELEPORT                ; it vanishes in a spiral of sparks
        jsr fx_on_wait
        ldx origin_sq
        stx cur_sq
        lda board,x
        sta pick_slot
        sta held_slot
        lda #EMPTY
        sta board,x
        jsr held_to_square
        lda #MODE_TELEPORT
        sta move_mode
        lda #15
        sta move_range
        lda #1
        sta spell_move
        jsr move_icon
        lda #0
        sta spell_move
        clc
        rts

; sp_a = square: full lifespan
spell_heal:
        lda #FX_HEAL
        ldx sp_a
        jsr fx_on_wait
        ldx sp_a
        ldy board,x
        ldx slot_type,y
        lda type_life,x
        sta slot_hp,y
        clc
        rts

spell_shift:
        jsr fx_pulse
        lda lum_dir
        eor #1
        sta lum_dir
        clc
        rts

; sp_a, sp_b = squares: swap their icons. They leave the board as two orbs that fly
; past each other and land.
spell_exchange:
        ldx sp_a
        ldy sp_b
        lda board,x
        sta l_ex_icon
        lda board,y
        sta l_ex_icon+1
        lda #EMPTY
        sta board,x
        sta board,y
        lda sp_a
        ldy sp_b
        jsr l_ex_orb
        lda sp_b
        ldy sp_a
        jsr l_ex_orb
        jsr fx_wait
        ldx sp_a
        ldy sp_b
        lda l_ex_icon+1
        sta board,x
        lda l_ex_icon
        sta board,y
        clc
        rts
; an orb from square A to square Y
l_ex_orb:
        phy
        tax
        lda #FXF_LOOP
        sta fx_flags
        lda #FX_ORB
        jsr fx_on
        pla
        bcs +                           ; (no free slot: no orb)
        jsr fx_square
        jsr fx_fly
+       rts
l_ex_icon:      .byte 0, 0

; carry clear when some enemy icon stands off the power points
summon_possible:
        ldx #80
-       txa
        pha
        jsr enemy_at
        pla
        bcs +
        jsr is_power_point
        bcc _yes
+       tax
        dex
        bpl -
        sec
        rts
_yes:   clc
        rts

; pick a random elemental, never the last one summoned -> sp_a = its slot
summon_choose:
-       jsr rand
        and #3
        cmp last_elem
        beq -
        sta last_elem
        clc
        adc #$15                        ; AN AIR / A FIRE / AN EARTH / A WATER
        sta view_msg
        lda #$41                        ; ELEMENTAL APPEARS!
        sta view_msg2
        lda #MSG_FRAMES
        sta l_sm_t
-       jsr frame
        dec l_sm_t
        bne -
        lda #NO_SLOT                    ; the announcement is over
        sta view_msg
        sta view_msg2
        lda last_elem
        clc
        adc #SLOT_ELEM
        sta sp_a
        rts

; the elemental in sp_a flies in from beside the board and must attack an enemy
spell_summon_move:
        lda side
        sta elem_side
        ldx sp_a
        lda slot_type,x
        tay
        lda type_life,y
        sta slot_hp,x
        stx pick_slot
        stx held_slot
        ldx side
        lda l_elem_origin,x
        sta origin_sq
        lda l_elem_entry,x              ; the frame starts on the nearest edge square
        sta cur_sq
        sta cursor_sq
        jsr held_from_panel
        jsr fx_summon_burst
        jsr held_to_square
        lda #MODE_FLY
        sta move_mode
        lda #15
        sta move_range
        lda #$80
        sta spell_move
        jsr move_icon
        lda #0
        sta spell_move
        clc
        rts
l_elem_origin:  .byte SQ_OFF_LEFT, SQ_OFF_RIGHT
l_elem_entry:   .byte SQ_LIGHT_HOME, SQ_DARK_HOME

; Revive: fills panel_list with the side's dead types. Carry set (refusal shown) when
; none is dead or the charmed square has no opening.
revive_check:
        ldx side
        lda l_first_slot,x
        sta tmp6                        ; slot
        clc
        adc #SLOT_DARK
        sta tmp6+1
        ldy #0                          ; list length (also in tmp7)
        sty tmp7
_slot:  ldx tmp6
        lda slot_hp,x
        bne _next
        lda slot_type,x
        ldx #0                          ; already listed?
-       cpx tmp7
        beq _add
        cmp panel_list,x
        beq _next
        inx
        bra -
_add:   sta panel_list,y
        iny
        sty tmp7
        cpy #8
        beq _done
_next:  inc tmp6
        lda tmp6
        cmp tmp6+1
        bne _slot
_done:  lda #$ff
        sta panel_list,y
        cpy #0
        bne +
        lda #$13                        ; ALL YOUR ICONS LIVE
        bra _refuse
+       jsr charmed_opening
        bcc +
        lda #$12                        ; NO OPENING IN THE CHARMED SQUARE
_refuse:
        pha
        lda #$ff
        sta panel_list
        pla
        jsr show_message
        sec
+       rts

; carry clear when a square of the 3x3 block around mage_sq is empty and not a PP
charmed_opening:
        ldx #80
-       txa
        jsr in_charmed
        bcs +
        lda board,x
        bpl +
        txa
        jsr is_power_point
        bcc _yes
+       dex
        bpl -
        sec
        rts
_yes:   clc
        rts

; A = square -> carry clear when it is next to mage_sq (diagonals too), keeps X
in_charmed:
        phx
        jsr sq_rowcol
        sta tmp4
        stx tmp4+1
        lda mage_sq
        jsr sq_rowcol
        sec
        sbc tmp4
        clc
        adc #1
        cmp #3                          ; |drow| <= 1
        bcs _no
        txa
        sec
        sbc tmp4+1
        clc
        adc #1
        cmp #3
        bcs _no
        plx
        clc
        rts
_no:    plx
        sec
        rts

; sp_a = type, sp_b = square: revive its first dead slot there with full lifespan
spell_revive:
        ldx side
        lda l_first_slot,x
        tax
-       lda slot_type,x
        cmp sp_a
        bne +
        lda slot_hp,x
        beq _found
+       inx
        bra -
_found: ldy sp_a
        lda type_life,y
        sta slot_hp,x
        stx l_rv_slot
        lda #FX_REVIVE                  ; a beam of light comes down, and it is there
        ldx sp_b
        jsr fx_on
        lda #REVIVE_APPEARS
        jsr wait_frames
        lda l_rv_slot
        ldx sp_b
        sta board,x
        jsr fx_wait
        clc
        rts
REVIVE_APPEARS  = 14                    ; frames into the beam
l_rv_slot:      .byte 0

; carry set when imprisoning now would be wasted (the cycle already frees the foe)
imprison_possible:
        lda side
        bne _dark
        lda lum_level                   ; Light imprisons Dark icons: freed at black
        beq _no
        clc
        rts
_dark:  lda lum_level                   ; Dark imprisons Light icons: freed at white
        cmp #LUM_LEVELS - 1
        beq _no
        clc
        rts
_no:    sec
        rts

; sp_a = square of the enemy: it is the prisoner of its side
spell_imprison:
        lda #FX_IMPRISON                ; the links fly in and lock
        ldx sp_a
        jsr fx_on_wait
        ldx sp_a
        lda board,x
        ldx side
        cpx #SIDE_LIGHT
        bne +
        sta prisoner+SIDE_DARK
        clc
        rts
+       sta prisoner+SIDE_LIGHT
        clc
        rts
