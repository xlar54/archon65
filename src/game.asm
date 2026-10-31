;=======================================================================================
; game.asm - the rules of the strategy game.
;
;   game_play      one whole game from the current options; returns at the end with
;                  game_result set
;   square_lum     A = board square -> A = luminance L 0 (black) .. 7 (white)
;   slot_side      X = slot -> A = SIDE_LIGHT / SIDE_DARK (elementals: the summoner's)
;
; Sides are 0 (Light) and 1 (Dark). The board holds a slot per square or EMPTY. Slots
; 0-17 are Light, 18-35 Dark, 36-39 the elementals (tables in src/assets/tables.asm).
; The luminance cycle runs through 6 levels (black blue purple green cyan white) that
; correspond to the original's L = 0 1 3 4 6 7.
;=======================================================================================

SIDE_LIGHT      = 0
SIDE_DARK       = 1
EMPTY           = $80
NO_SLOT         = $ff
SLOT_DARK       = 18                    ; first Dark slot
SLOT_ELEM       = 36                    ; first elemental slot
TYPE_WIZARD     = 1
TYPE_SORCERESS  = 9
TYPE_SHIFTER    = 12
LUM_LEVELS      = 6
SQ_LIGHT_HOME   = 4 * 9 + 0             ; the mages' power points
SQ_DARK_HOME    = 4 * 9 + 8
NSPELLS         = 7

RESULT_NONE     = 0
RESULT_LIGHT    = 1
RESULT_DARK     = 2
RESULT_TIE      = 3
RESULT_STALE    = 4
RESULT_QUIT     = 5

; ---- options (title screen) ----
opt_cpu:        .byte 0                 ; bit 0 = computer plays Light, bit 1 = Dark
opt_first:      .byte SIDE_LIGHT        ; side that moves first

; ---- game state ----
board:          .fill 81
slot_hp:        .fill NSLOTS            ; stored lifespan, 0 = dead
spell_used:     .fill 2 * NSPELLS       ; side * 7 + spell: 0 available, 1 cast
spells_cast:    .fill 2
prisoner:       .fill 2                 ; imprisoned slot per side, or NO_SLOT
lum_level:      .byte 0                 ; 0..5
lum_dir:        .byte 0                 ; 0 = getting lighter, 1 = darker
half_turn:      .byte 0
side:           .byte 0                 ; side to move
stalemate:      .byte 0                 ; 0 = not armed, else turn pairs left
last_elem:      .byte NO_SLOT
game_result:    .byte 0
turn_count:     .byte 0
living:         .fill 2                 ; living icons per side (counted each turn)

lum_to_l:       .byte 0, 1, 3, 4, 6, 7

; test hook: poke dbg_fight = attacking slot, dbg_fight_sq = the
; square it attacks; the game then opens with that fight
dbg_fight:      .byte $ff
dbg_fight_sq:   .byte 0

;---------------------------------------------------------------------------------------
game_new:
        ldx #80
-       lda board_start,x
        sta board,x
        dex
        bpl -
        ldx #NSLOTS - 1
-       ldy slot_type,x
        lda type_life,y
        sta slot_hp,x
        dex
        bpl -
        ldx #2 * NSPELLS - 1
        lda #0
-       sta spell_used,x
        dex
        bpl -
        sta spells_cast
        sta spells_cast+1
        sta half_turn
        sta stalemate
        sta game_result
        sta turn_count
        lda #NO_SLOT
        sta prisoner
        sta prisoner+1
        sta last_elem
        ; Light first: green getting darker; Dark first: purple getting lighter
        ldx opt_first
        lda l_start_level,x
        sta lum_level
        lda l_start_dir,x
        sta lum_dir
        txa
        eor #1                          ; the loop flips the side before each turn
        sta side
        jmp board_reset_cursors
l_start_level:  .byte 3, 2
l_start_dir:    .byte 1, 0

;---------------------------------------------------------------------------------------
game_play:
        jsr game_new
        lda dbg_fight                   ; test hook: a fight straight away
        bmi _turn
        sta fight_attacker
        ldy #80
-       lda board,y                     ; (the attacker leaves its square)
        cmp fight_attacker
        bne +
        lda #EMPTY
        sta board,y
+       dey
        bpl -
        lda dbg_fight_sq
        sta fight_square
        jsr fight_square_now
        lda #$ff
        sta dbg_fight
_turn:  lda side
        eor #1
        sta side
        jsr check_power_points
        bne _over
        jsr count_living
        bne _over
        lda half_turn
        eor #1
        sta half_turn
        beq +
        jsr turn_pair
        lda game_result
        bne _over
+       jsr check_last_prisoner
        bne _over
        inc turn_count
        jsr side_is_cpu
        bne _cpu
        jsr human_turn
        bra _done
_cpu:   jsr arm_stalemate
        jsr ai_turn
_done:  lda game_result                 ; a quit, or a combat that ended the game
        beq _turn
_over:  rts

; Z clear (A != 0) when the side to move is a computer player
side_is_cpu:
        ldx side
        lda opt_cpu
        and l_side_bit,x
        rts
l_side_bit:     .byte 1, 2

;---------------------------------------------------------------------------------------
; the every-second-turn step: stalemate count, luminance, healing
turn_pair:
        lda stalemate
        beq +
        dec stalemate
        bne +
        lda #RESULT_STALE
        sta game_result
        rts
+       jsr lum_step
        ; +1 HP for every icon on a power point
        ldy #4
-       ldx pp_square,y
        lda board,x
        bmi +
        tax
        jsr heal_one
+       dey
        bpl -
        rts

; step the luminance one level; at an extreme free that side's prisoner and heal it
lum_step:
        lda lum_dir
        bne _dark
        lda lum_level                   ; lighter (from white: jump to black)
        cmp #LUM_LEVELS - 1
        bcc +
        lda #$ff
+       inc a
        bra _set
_dark:  lda lum_level                   ; darker (from black: jump to white)
        bne +
        lda #LUM_LEVELS
+       dec a
_set:   sta lum_level
        beq _black
        cmp #LUM_LEVELS - 1
        bne _out
        lda #1                          ; white: now getting darker; Light benefits
        sta lum_dir
        ldx #SIDE_LIGHT
        bra _extreme
_black: lda #0
        sta lum_dir
        ldx #SIDE_DARK
_extreme:
        lda #NO_SLOT
        sta prisoner,x
        jmp heal_side
_out:   rts

; X = side: +1 HP to each of its living, wounded icons
heal_side:
        lda l_first_slot,x
        sta tmp7
        clc
        adc #SLOT_DARK
        sta tmp7+1
-       ldx tmp7
        lda slot_hp,x
        beq +
        jsr heal_one
+       inc tmp7
        lda tmp7
        cmp tmp7+1
        bne -
        rts
l_first_slot:   .byte 0, SLOT_DARK

; X = slot: +1 HP up to its lifespan (keeps X and Y)
heal_one:
        phy
        ldy slot_type,x
        lda slot_hp,x
        cmp type_life,y
        bcs +
        inc slot_hp,x
+       ply
        rts

;---------------------------------------------------------------------------------------
; all five power points held by one side -> that side wins. A != 0 when over.
check_power_points:
        ldx pp_square
        lda board,x
        bmi _no
        tax
        jsr slot_side
        sta tmp0
        ldy #4
-       ldx pp_square,y
        lda board,x
        bmi _no
        tax
        jsr slot_side
        cmp tmp0
        bne _no
        dey
        bne -
        ldx tmp0
        lda l_win,x
        sta game_result
        rts
_no:    lda #0
        rts
l_win:          .byte RESULT_LIGHT, RESULT_DARK

; living icons per side -> living; a side with none loses. A != 0 when over.
count_living:
        lda #0
        sta living
        sta living+1
        ldx #SLOT_ELEM - 1
-       lda slot_hp,x
        beq +
        jsr slot_side
        tay
        lda living,y
        inc a
        sta living,y
+       dex
        bpl -
        lda living
        ora living+1
        bne +
        lda #RESULT_TIE
        bra _set
+       lda living
        bne +
        lda #RESULT_DARK
        bra _set
+       lda living+1
        bne _no
        lda #RESULT_LIGHT
_set:   sta game_result
        rts
_no:    lda #0
        rts

; the side to move has exactly one icon and it is imprisoned -> it loses
check_last_prisoner:
        ldx side
        lda living,x
        cmp #1
        bne _no
        lda prisoner,x
        bmi _no
        txa
        eor #1
        tax
        lda l_win,x
        sta game_result
        rts
_no:    lda #0
        rts

; a computer is playing and both sides are down to two icons: start the countdown
arm_stalemate:
        lda stalemate
        bne +
        lda living
        cmp #3
        bcs +
        lda living+1
        cmp #3
        bcs +
        lda #12
        sta stalemate
+       rts

;---------------------------------------------------------------------------------------
; X = slot -> A = side (elementals belong to the side that summoned them)
slot_side:
        cpx #SLOT_DARK
        bcc _light
        cpx #SLOT_ELEM
        bcc _dark
        lda elem_side
        rts
_light: lda #SIDE_LIGHT
        rts
_dark:  lda #SIDE_DARK
        rts
elem_side:      .byte 0

; A = square -> A = L (0..7)
square_lum:
        tax
        lda square_kind,x
        beq +                           ; always dark: 0
        cmp #1
        bne ++
        lda #7                          ; always light
+       rts
+       ldx lum_level
        lda lum_to_l,x
        rts

; A = square -> carry set when it is a power point (keeps X)
is_power_point:
        ldy #4
-       cmp pp_square,y
        beq +
        dey
        bpl -
        clc
        rts
+       sec
        rts

;---------------------------------------------------------------------------------------
; fight_square - the icon in slot fight_attacker attacks the square fight_square.
; Runs the combat and applies the result (rules.md 3.4).
fight_attacker: .byte 0
fight_square:   .byte 0

fight_square_now:
        ldx fight_square
        lda board,x
        sta tmp0                        ; defender
        ldx fight_attacker
        jsr slot_side
        tay                             ; attacker's side
        lda fight_attacker
        sta combat_slot,y
        tya
        eor #1
        tay
        lda tmp0
        sta combat_slot,y
        lda fight_square
        sta combat_square
        jsr combat_run
        lda #0
        sta stalemate
        ; write back each side
        ldy #1
-       ldx combat_slot,y
        cpx #SLOT_ELEM
        bcs _next                       ; elementals vanish
        lda combat_hp,y
        bne _alive
        sta slot_hp,x                   ; dead
        txa
        cmp prisoner,y
        bne _next
        lda #NO_SLOT
        sta prisoner,y
        bra _next
_alive: lda slot_type,x
        cmp #TYPE_SHIFTER
        beq _next                       ; rebuilt for every fight
        lda combat_hp,y
        cmp slot_hp,x
        bcs _next
        sta slot_hp,x
_next:  dey
        bpl -
        ; the square goes to the surviving non-elemental icon, if any
        ldx fight_square
        lda #EMPTY
        sta board,x
        ldy #1
-       lda combat_hp,y
        beq +
        lda combat_slot,y
        cmp #SLOT_ELEM
        bcs +
        sta board,x
+       dey
        bpl -
        rts
