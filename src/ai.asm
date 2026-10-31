;=======================================================================================
; ai.asm - the computer player.
;
;   ai_turn          one board turn for `side`: a spell if a rule calls for one, else the
;                    best scoring move, shown as a player would make it
;   ai_combat_start  per-fighter parameters at the start of a fight
;   ai_combat        X = fighter: this frame's controls into f_stick,x
;
; Board scores are 8-bit and wrap, as in the original. Ground moves are checked with a
; breadth-first search over empty squares (the original used path tables; BFS allows a
; few more detours).
;=======================================================================================

AI_THINK        = 64                    ; frames before the computer acts (96 in the demo)
AI_THINK_DEMO   = 96
AI_STEP         = 8                     ; frames per square while its icon moves
SLOT_WIZARD     = 8
SLOT_SORCERESS  = 27

ai_best:        .byte 0                 ; best improvement over all pieces
ai_piece:       .byte 0                 ; the chosen slot
ai_origin:      .byte 0
ai_dest:        .byte 0
ai_base:        .byte 0                 ; the candidate's score where it stands
ai_cbest:       .byte 0                 ; best for this candidate
ai_cdest:       .byte 0
ai_dmg:         .byte 0                 ; candidate: lifespan - life
ai_maxl:        .byte 0                 ;   its lifespan
ai_endgame:     .byte 0
ai_material:    .byte 0                 ; signed: own - enemy pieces in the endgame
ai_ppmode:      .byte 0                 ; a side holds 4 power points
ai_count:       .fill 2                 ; pieces on the board per side
cand_score:     .fill 81                ; per origin square: its best improvement
cand_dest:      .fill 81                ;   and where to ($ff = not a candidate)

;---------------------------------------------------------------------------------------
ai_turn:
        lda side
        jsr sound_turn
        lda #AI_THINK
        ldx demo
        beq +
        lda #AI_THINK_DEMO
+       jsr wait_frames
        lda game_result
        bne _out
        jsr ai_spells
        bcs _out                        ; a spell was cast
        jsr ai_plan
        jsr ai_execute
_out:   rts

;---------------------------------------------------------------------------------------
; helpers

; A = square -> A = how much its colour favours the computer's side (0..7)
ai_favour:
        phx
        phy
        jsr square_lum
        ldx side
        beq +
        eor #7
+       ply
        plx
        rts

; A = square -> carry set when the square holds an icon of `side`
ai_own_at:
        tax
        lda board,x
        bmi _no
        tax
        jsr slot_side
        cmp side
        bne _no
        sec
        rts
_no:    clc
        rts

; dest_score (S7105): A = square -> A = score, carry set when invalid (own icon)
ai_score:
        sta l_as_sq
        jsr ai_own_at
        bcc +
        rts
+       lda l_as_sq
        jsr ai_favour
        sta l_as_f
        ; b: the spell penalty of a home power point (minus on our own, plus on theirs)
        lda #0
        sta l_as_b
        ldx #SIDE_LIGHT
        lda l_as_sq
        cmp #SQ_LIGHT_HOME
        beq _home
        ldx #SIDE_DARK
        cmp #SQ_DARK_HOME
        bne _nob
_home:  lda spells_cast,x
        lsr
        cpx side
        bne +
        eor #$ff
        inc a
+       sta l_as_b
_nob:   lda #0
        sta l_as_x
        sta l_as_em
        ldx l_as_sq
        lda board,x
        bmi _sum
        tax                             ; an enemy: what attacking it is worth
        ldy slot_type,x
        lda type_life,y
        sta l_as_em
        sec
        sbc slot_hp,x
        sec
        sbc #3
        sec
        sbc ai_dmg
        clc
        adc l_as_b
        clc
        adc l_as_f
        clc
        adc ai_material
        ldx l_as_b
        bmi +
        clc
        adc l_as_b
+       sta l_as_x
_sum:   ldx l_as_sq
        lda ai_pos_value,x
        clc
        adc l_as_f
        clc
        adc l_as_b
        clc
        adc l_as_x
        sta l_as_s
        lda ai_endgame
        beq +
        lda l_as_em
        beq +
        lda l_as_s
        clc
        adc ai_maxl
        sec
        sbc l_as_em
        sta l_as_s
+       lda ai_ppmode
        beq +
        lda l_as_sq
        jsr is_power_point
        bcc +
        lda l_as_s
        clc
        adc #6
        sta l_as_s
+       lda l_as_s
        clc
        rts
l_as_sq:        .byte 0
l_as_f:         .byte 0
l_as_b:         .byte 0
l_as_x:         .byte 0
l_as_em:        .byte 0
l_as_s:         .byte 0

; random 0..A-1 (A <= 128)
ai_rand_below:
        sta l_rb_n
        dec a                           ; mask = next power of two - 1
        ora #0
        ldx #0
-       cmp #0
        beq +
        lsr
        inx
        bra -
+       lda #0
-       cpx #0
        beq +
        sec
        rol
        dex
        bra -
+       sta l_rb_m
-       jsr rand
        and l_rb_m
        cmp l_rb_n
        bcs -
        rts
l_rb_n:         .byte 0
l_rb_m:         .byte 0

;---------------------------------------------------------------------------------------
; ai_plan - choose ai_piece / ai_origin / ai_dest (planner S6D3C steps 2-5)
ai_plan:
        ; counts on the board, endgame, material, power-point mode
        lda #0
        sta ai_count
        sta ai_count+1
        ldx #80
-       lda board,x
        bmi +
        phx
        tax
        jsr slot_side
        tay
        lda ai_count,y
        inc a
        sta ai_count,y
        plx
+       dex
        bpl -
        lda #0
        sta ai_endgame
        sta ai_material
        lda ai_count
        cmp #5
        bcc _end
        lda ai_count+1
        cmp #5
        bcs _noend
_end:   lda #1
        sta ai_endgame
        ldx side
        txa
        eor #1
        tay
        lda ai_count,x
        sec
        sbc ai_count,y
        sta ai_material
_noend: jsr ai_pp_mode
        ; every own piece: its best destination
        lda #0
        sta ai_best
        ldx #80
_cand:  stx l_ap_sq
        lda #$ff
        sta cand_dest,x
        lda board,x
        bmi _next
        sta ai_piece
        ldy side                        ; not the imprisoned one
        cmp prisoner,y
        beq _next
        tax
        jsr slot_side
        cmp side
        bne _next
        ldx l_ap_sq
        jsr ai_candidate
_next:  ldx l_ap_sq
        dex
        bpl _cand
        ; the pieces with the best score: pick one at random
        lda #0
        sta l_ap_n
        ldx #80
-       lda cand_dest,x
        cmp #$ff
        beq +
        lda cand_score,x
        cmp ai_best
        bne +
        inc l_ap_n
+       dex
        bpl -
        lda l_ap_n
        jsr ai_rand_below
        sta l_ap_n
        ldx #80
-       lda cand_dest,x
        cmp #$ff
        beq +
        lda cand_score,x
        cmp ai_best
        bne +
        lda l_ap_n
        beq _pick
        dec l_ap_n
+       dex
        bpl -
        rts                             ; (cannot happen: some piece can always move)
_pick:  stx ai_origin
        lda board,x
        sta ai_piece
        lda cand_dest,x
        sta ai_dest
        rts
l_ap_n:         .byte 0
l_ap_sq:        .byte 0

; how many power points each side holds: 4 of 5 = power-point mode
ai_pp_mode:
        lda #0
        sta ai_ppmode
        sta l_pp_n
        sta l_pp_n+1
        ldy #4
-       ldx pp_square,y
        lda board,x
        bmi +
        tax
        jsr slot_side
        tax
        inc l_pp_n,x
+       dey
        bpl -
        lda l_pp_n
        cmp #4
        beq +
        lda l_pp_n+1
        cmp #4
        bne ++
+       lda #1
        sta ai_ppmode
+       rts
l_pp_n:         .fill 2

; the candidate ai_piece on square X (= ai_origin): cand_score / cand_dest
ai_candidate:
        stx ai_origin
        ldy ai_piece
        ldx slot_type,y
        lda type_life,x
        sta ai_maxl
        sec
        sbc slot_hp,y
        sta ai_dmg
        lda type_move,x
        sta l_ac_move
        and #$0f
        sta l_ac_rng
        ; base = pos - 30 - b + favour + 6 on a power point in PP mode
        ldx ai_origin
        lda ai_pos_value,x
        sec
        sbc #30
        sta ai_base
        ldy side
        lda l_home,y
        cmp ai_origin
        bne +
        lda spells_cast,y
        lsr
        sta tmp0
        lda ai_base
        sec
        sbc tmp0
        sta ai_base
+       lda ai_origin
        jsr ai_favour
        clc
        adc ai_base
        sta ai_base
        lda ai_ppmode
        beq +
        lda ai_origin
        jsr is_power_point
        bcc +
        lda ai_base
        clc
        adc #6
        sta ai_base
+       lda #0
        sta ai_cbest
        lda #$ff
        sta ai_cdest
        ; destinations: a box (fliers, teleporters) or a diamond (ground), high to low
        lda ai_origin
        jsr sq_rowcol
        sta l_ac_r
        stx l_ac_c
        lda l_ac_r
        clc
        adc l_ac_rng
        cmp #9
        bcc +
        lda #8
+       sta l_ac_row
_row:   ; column span: the full range, or what is left of it for a ground mover
        lda l_ac_rng
        ldx l_ac_move
        bmi _span
        lda l_ac_row
        sec
        sbc l_ac_r
        bcs +
        eor #$ff
        inc a
+       sta tmp0
        lda l_ac_rng
        sec
        sbc tmp0
_span:  sta l_ac_w
        lda l_ac_c
        clc
        adc l_ac_w
        cmp #9
        bcc +
        lda #8
+       sta l_ac_col
        lda l_ac_c
        sec
        sbc l_ac_w
        bcs +
        lda #0
+       sta l_ac_cmin
_col:   lda l_ac_row                    ; square = row * 9 + col
        asl
        asl
        asl
        adc l_ac_row
        adc l_ac_col
        sta l_ac_sq
        jsr ai_score
        bcs _skip
        sec
        sbc ai_base                     ; improvement, 8-bit unsigned
        sta l_ac_imp
        cmp ai_cbest
        bcc _skip
        lda l_ac_move
        bmi _ok                         ; fliers go anywhere in range
        lda l_ac_imp
        cmp ai_best
        bcc _skip
        lda l_ac_sq
        jsr ai_path
        bcc _skip
_ok:    lda l_ac_imp
        cmp ai_cbest
        bne _take
        lda ai_cdest                    ; an equal square: 1 in 3 takes the later one
        cmp #$ff
        beq _take
-       jsr rand
        and #3
        beq -
        cmp #2
        bcs _skip
_take:  lda l_ac_imp
        sta ai_cbest
        lda l_ac_sq
        sta ai_cdest
_skip:  lda l_ac_col
        cmp l_ac_cmin
        beq +
        dec l_ac_col
        bra _col
+       ; next row up, down to r - range
        lda l_ac_row
        beq _done
        sec
        sbc l_ac_r
        bcs +                           ; row >= r: keep going
        eor #$ff
        inc a
        cmp l_ac_rng
        bcs _done
+       dec l_ac_row
        jmp _row
_done:  ldx ai_origin
        lda ai_cdest
        sta cand_dest,x
        lda ai_cbest
        sta cand_score,x
        lda ai_cdest
        cmp #$ff
        beq +
        lda ai_cbest
        cmp ai_best
        bcc +
        sta ai_best
+       rts
l_ac_move:      .byte 0
l_ac_rng:       .byte 0
l_ac_r:         .byte 0
l_ac_c:         .byte 0
l_ac_row:       .byte 0
l_ac_col:       .byte 0
l_ac_cmin:      .byte 0
l_ac_w:         .byte 0
l_ac_sq:        .byte 0
l_ac_imp:       .byte 0

; A = destination: carry set when ai_origin's ground mover can reach it in l_ac_rng
; orthogonal steps over empty squares (the destination may hold an enemy). Leaves the
; route in bfs_from for ai_execute.
ai_path:
        sta l_bf_dest
        cmp ai_origin
        beq _no
        ldx #80
        lda #$ff
-       sta bfs_dist,x
        dex
        bpl -
        ldx ai_origin
        lda #0
        sta bfs_dist,x
        stx bfs_queue
        lda #0
        sta l_bf_head
        lda #1
        sta l_bf_tail
_pop:   ldx l_bf_head
        cpx l_bf_tail
        beq _no
        lda bfs_queue,x
        sta l_bf_sq
        inc l_bf_head
        tax
        lda bfs_dist,x
        cmp l_ac_rng
        bcs _pop                        ; no steps left from here
        inc a
        sta l_bf_d
        ldx #3
_dir:   stx l_bf_dir
        lda l_bf_nb_lo,x                ; the neighbour from the tables
        sta str_ptr
        lda l_bf_nb_hi,x
        sta str_ptr+1
        ldy l_bf_sq
        lda (str_ptr),y
        cmp #$ff
        beq _nextdir
        tay
        lda bfs_dist,y
        cmp #$ff
        bne _nextdir                    ; seen
        lda l_bf_d
        sta bfs_dist,y
        lda l_bf_sq
        sta bfs_from,y
        cpy l_bf_dest
        beq _yes
        lda board,y
        bpl _nextdir                    ; occupied: can't pass
        ldx l_bf_tail
        tya
        sta bfs_queue,x
        inc l_bf_tail
_nextdir:
        ldx l_bf_dir
        dex
        bpl _dir
        bra _pop
_yes:   sec
        rts
_no:    clc
        rts
l_bf_dest:      .byte 0
l_bf_head:      .byte 0
l_bf_tail:      .byte 0
l_bf_sq:        .byte 0
l_bf_d:         .byte 0
l_bf_nb_lo:     .byte <sq_up, <sq_down, <sq_left, <sq_right
l_bf_nb_hi:     .byte >sq_up, >sq_down, >sq_left, >sq_right
l_bf_dir:       .byte 0
bfs_dist:       .fill 81
bfs_from:       .fill 81
bfs_queue:      .fill 81

;---------------------------------------------------------------------------------------
; ai_execute - show the chosen move, then make it (combat on an enemy square)
ai_execute:
        lda ai_origin
        sta cursor_sq
        lda #AI_STEP * 2
        jsr wait_frames
        ldx ai_origin                   ; pick it up
        stx origin_sq
        stx cur_sq
        lda #EMPTY
        sta board,x
        lda ai_piece
        sta pick_slot
        sta held_slot
        tax
        jsr move_rules
        jsr held_to_square
        lda ai_piece
        tax
        lda slot_type,x
        clc
        adc #$1c                        ; NAME (MOVE n)
        sta view_msg
        lda move_mode
        bne _fly
        ; ground: walk the route found by the search, from the destination back
        lda ai_dest
        jsr ai_path_refresh
        ldx #0
        lda ai_dest
-       sta path,x                      ; the route, reversed
        inx
        tay
        lda bfs_from,y
        cmp ai_origin
        bne -
        stx path_len
_walk:  dec path_len
        bmi _drop
        ldx path_len
        lda path,x
        jsr l_ai_step_to
        bra _walk
_fly:   ; fliers and teleporters: the frame heads straight for the destination
        lda cur_sq
        cmp ai_dest
        beq _drop
        jsr l_ai_toward
        jsr l_ai_step_to
        bra _fly
_drop:  lda ai_dest
        sta cur_sq
        lda #0
        sta spell_move
        jmp ai_drop

; the destination's route again (the planner's later searches overwrote bfs_from)
ai_path_refresh:
        pha
        ldx ai_piece
        jsr move_rules
        lda move_range
        sta l_ac_rng
        pla
        jmp ai_path

; A = square: the frame (and a flier / walker) moves there, then a pause
l_ai_step_to:
        sta cur_sq
        sta cursor_sq
        lda move_mode
        cmp #MODE_TELEPORT
        beq +
        jsr held_to_square
+       lda #AI_STEP
        jmp wait_frames

; one diagonal or straight step from cur_sq toward ai_dest -> A
l_ai_toward:
        lda ai_dest
        jsr sq_rowcol
        sta tmp6
        stx tmp6+1
        lda cur_sq
        jsr sq_rowcol
        sta tmp7
        stx tmp7+1
        ldx #0
        lda tmp7
        cmp tmp6
        beq +
        ldx #JOY_DOWN
        bcc +
        ldx #JOY_UP
+       stx tmp3
        ldx #0
        lda tmp7+1
        cmp tmp6+1
        beq +
        ldx #JOY_RIGHT
        bcc +
        ldx #JOY_LEFT
+       txa
        ora tmp3
        tax
        lda cur_sq
        jmp sq_step

; drop the held icon (pick_slot) on cur_sq: place it, or fight for the square
ai_drop:
        ldx cur_sq
        lda board,x
        bmi _place
        lda pick_slot
        sta fight_attacker
        lda cur_sq
        sta fight_square
        jsr l_drop_done
        jmp fight_square_now
_place: lda pick_slot
        sta board,x
        lda move_mode                   ; a teleporter shimmers in
        cmp #MODE_TELEPORT
        bne +
        txa
        jsr board_teleported
+       jmp l_drop_done

;=======================================================================================
; spells (S6D3C step 1): rules tried in the order Imprison, Shift Time, Summon,
; Teleport, Revive, Heal (Exchange is never cast). Carry set when one was cast.
;=======================================================================================
ai_spells:
        ldx side
        lda l_ai_mage,x
        sta tmp0
        tax
        lda slot_hp,x
        beq _no                         ; the mage is dead
        ldx side
        lda prisoner,x
        cmp tmp0
        beq _no                         ; or imprisoned
        lda #0
        sta l_ais_i
_try:   ldx l_ais_i
        lda l_ai_order,x
        sta sp_choice
        jsr l_available
        bne _next
        lda sp_choice
        asl
        tax
        jsr (l_ai_eval,x)
        bcs _cast
_next:  inc l_ais_i
        lda l_ais_i
        cmp #6
        bne _try
_no:    clc
        rts
_cast:  ; tell the player, then the effect (X = the effect routine)
        ldx side
        lda l_ai_mage_msg,x
        sta view_msg
        lda #$42                        ; CONJURES A SPELL!
        sta view_msg2
        lda #MSG_FRAMES
        jsr wait_frames
        lda sp_choice
        clc
        adc #MSG_SPELL_NAME
        sta view_msg
        lda #NO_SLOT
        sta view_msg2
        lda #MSG_FRAMES
        jsr wait_frames
        lda sp_choice
        asl
        tax
        jsr (l_ai_do,x)
        jsr l_spell_base                ; the spell is used
        txa
        clc
        adc sp_choice
        tax
        lda #1
        sta spell_used,x
        ldx side
        inc spells_cast,x
        lda #NO_SLOT
        sta view_msg
        sec
        rts
l_ais_i:        .byte 0
l_ai_mage:      .byte SLOT_WIZARD, SLOT_SORCERESS
l_ai_mage_msg:  .byte $1a, $1b
l_ai_order:     .byte SP_IMPRISON, SP_SHIFT, SP_SUMMON, SP_TELEPORT, SP_REVIVE, SP_HEAL
; by spell number (Exchange, 3, is never evaluated)
l_ai_eval:      .word ai_eval_teleport, ai_eval_heal, ai_eval_shift, 0, ai_eval_summon
                .word ai_eval_revive, ai_eval_imprison
l_ai_do:        .word ai_do_teleport, spell_heal, spell_shift, 0, ai_do_summon, spell_revive
                .word spell_imprison

; the enemy mage's square if it lives, is free and off the power points -> A, carry set
ai_enemy_mage:
        lda side
        eor #1
        tax
        lda l_ai_mage,x
        sta tmp1
        tay
        lda slot_hp,y
        beq _no
        ldx #80
-       lda board,x
        cmp tmp1
        beq +
        dex
        bpl -
        bra _no
+       txa
        jsr is_power_point
        bcs _no
        txa
        sec
        rts
_no:    clc
        rts

; Imprison (S7524): the enemy mage, or an intruder in our half
ai_eval_imprison:
        jsr imprison_possible
        bcs _no
        jsr l_ai_heading_ours
        bcs +
        lda #SP_SHIFT                   ; heading the wrong way: only if we can turn it
        jsr l_ai_own_spent
        bcs _no
        jsr l_ai_lum_ok_against
        bcc _no
+       jsr ai_enemy_mage
        bcs _target
        jsr l_ai_heading_ours
        bcc _no
        lda #SP_SHIFT                   ; can the enemy still turn time against us?
        jsr l_ai_enemy_spent
        bcs _late
        lda #SP_SHIFT
        jsr l_ai_own_spent
        bcs _no
        lda opt_first
        cmp side
        bne _late
        lda lum_level                   ; we moved first: not too early in the swing
        ldx side
        bne +
        cmp #2
        bcc _no
        bra _late
+       cmp #4
        bcs _no
_late:  lda lum_level                   ; and not too late either
        ldx side
        bne +
        cmp #4
        bcs _no
        bra _pick
+       cmp #2
        bcc _no
_pick:  jsr ai_intruder
        bcs _target
        jsr ai_strong_on_bad
        bcc _no
_target:
        sta sp_a
        sec
        rts
_no:    clc
        rts

; Shift Time (S76D6)
ai_eval_shift:
        jsr l_ai_heading_ours
        bcc _away
        ; heading our way: only to free our prisoner from an extreme
        lda lum_level
        beq +
        cmp #LUM_LEVELS - 1
        bne _no
+       ldx side
        lda prisoner,x
        bmi _no
        sec
        rts
_away:  lda lum_level                   ; heading away: in our half of the cycle only
        ldx side
        bne +
        cmp #3
        bcs _no
        bra ++
+       cmp #3
        bcc _no
+       ldx side
        lda prisoner,x
        bmi +
        lda opt_first                   ; our prisoner: if we moved first, or they can't undo
        cmp side
        beq _yes
        lda #SP_SHIFT
        jsr l_ai_enemy_spent
        bcs _yes
        bra _no
+       txa
        eor #1
        tax
        lda prisoner,x
        bpl _yes                        ; theirs: keep it locked
        lda #SP_IMPRISON                ; both Imprisons and their Shift Time are spent:
        jsr l_ai_own_spent              ;   swing the cycle back ourselves
        bcc _no
        lda #SP_IMPRISON
        jsr l_ai_enemy_spent
        bcc _no
        lda #SP_SHIFT
        jsr l_ai_enemy_spent
        bcs _yes
_no:    clc
        rts
_yes:   sec
        rts

; Summon (S7752): the enemy mage, an intruder, or a strong icon on our colour
ai_eval_summon:
        jsr summon_possible
        bcs _no
        jsr ai_enemy_mage
        bcs _yes
        jsr ai_intruder
        bcs _yes
        jsr ai_strong_on_bad
        bcc _no
        sta sp_b
        tax
        lda square_kind,x
        cmp #2
        bne +
        lda lum_level                   ; a luminance square: only near our extreme
        ldx side
        bne _d
        cmp #4
        bcc _no
        bra +
_d:     cmp #2
        bcs _no
+       lda sp_b
_yes:   sta sp_b                        ; (the elemental's target)
        sec
        rts
_no:    clc
        rts

; Teleport (S7796): a back-rank icon onto the enemy mage; else, sometimes, a random
; back-rank icon: a Golem / Troll to a good square near the enemy, anything else onto
; the enemy's mirrored back-rank icon when that square's colour favours us
ai_eval_teleport:
        jsr ai_enemy_mage
        bcs +
        jmp ai_teleport_random
+       sta sp_b
        tax                             ; an imprisoned mage on a luminance square: wait
        lda board,x                     ;   until the colour favours us
        jsr is_prisoner_a
        bcc _back
        lda square_kind,x
        cmp #2
        bne _back
        lda sp_b
        jsr ai_favour
        cmp #6
        bcc _no
_back:  ldx side
        lda l_back_col,x
        sta tmp2
        lda #5
        sta l_tp_i
_row:   ldy l_tp_i
        lda l_tp_rows,y                 ; rows 0 2 6 8 5 3 of our back column
        asl
        asl
        asl
        adc l_tp_rows,y
        adc tmp2
        sta sp_a
        jsr ai_own_at
        bcc _next
        ldx sp_a
        lda board,x
        tax
        jsr is_prisoner
        bcs _next
        lda sp_a
        jsr is_power_point
        bcs _next
        sec
        rts
_next:  dec l_tp_i
        bpl _row
_no:    clc
        rts
l_tp_i:         .byte 0
l_tp_rows:      .byte 3, 5, 8, 6, 2, 0
l_back_col:     .byte 0, 8

; A = slot -> carry set when it is imprisoned (keeps X)
is_prisoner_a:
        phx
        tax
        jsr is_prisoner
        plx
        rts

ai_teleport_random:
        jsr rand                        ; 1 time in 4
        and #3
        bne _no
-       jsr rand                        ; a row of our back column
        and #15
        cmp #9
        bcs -
        sta l_tr_row
        asl
        asl
        asl
        adc l_tr_row
        ldx side
        adc l_back_col,x
        sta sp_a
        jsr ai_own_at
        bcc _no
        ldx sp_a
        lda board,x
        jsr is_prisoner_a
        bcs _no
        lda sp_a
        jsr is_power_point
        bcs _no
        ldx sp_a
        lda board,x
        tax
        lda slot_type,x
        and #7
        cmp #3                          ; Golem / Troll
        beq _heavy
        ; the enemy's icon on the mirrored row of its back column
        lda #8
        sec
        sbc l_tr_row
        sta tmp0
        asl
        asl
        asl
        adc tmp0
        ldx side
        ldy l_enemy_col,x
        sta tmp0
        tya
        clc
        adc tmp0
        sta sp_b
        jsr enemy_at
        bcs _no
        lda sp_b
        jsr is_power_point
        bcs _no
        ldx sp_b                        ; its colour must be ours: fixed, or the extreme
        lda square_kind,x
        cmp #2
        beq _lum
        lda sp_b
        jsr ai_favour
        cmp #7
        bne _no
        sec
        rts
_lum:   ldx side
        lda lum_level
        cmp l_tr_extreme,x
        bne _no
        sec
        rts
_no:    clc
        rts
_heavy: jsr rand                        ; 1 in 2
        lsr
        bcc _no
        ; the best empty square of rows 8-0 in the two columns before the enemy's ranks
        lda #47
        sta l_tr_best                   ; only scores of 48 and more
        lda #$ff
        sta sp_b
        ldx side
        lda l_heavy_col,x
        sta l_tr_col
        lda #8
        sta l_tr_row
_hrow:  lda #1
        sta l_tr_k
_hcol:  lda l_tr_row
        asl
        asl
        asl
        adc l_tr_row
        adc l_tr_col
        clc
        adc l_tr_k
        sta l_tr_sq
        tax
        lda board,x
        bpl _hnext                      ; (empty squares only)
        lda l_tr_sq
        jsr is_power_point
        bcs _hnext
        lda l_tr_sq
        jsr ai_score
        bcs _hnext
        cmp l_tr_best
        bcc _hnext
        beq _hnext
        sta l_tr_best
        lda l_tr_sq
        sta sp_b
_hnext: dec l_tr_k
        bpl _hcol
        dec l_tr_row
        bpl _hrow
        lda sp_b
        cmp #$ff
        beq _no
        sec
        rts
l_tr_row:       .byte 0
l_tr_col:       .byte 0
l_tr_k:         .byte 0
l_tr_sq:        .byte 0
l_tr_best:      .byte 0
l_enemy_col:    .byte 8, 0
l_heavy_col:    .byte 6, 1              ; columns 6-7 (Light), 1-2 (Dark)
l_tr_extreme:   .byte LUM_LEVELS - 1, 0  ; white for Light, black for Dark

; Revive (S7906): our Djinni / Phoenix (Light) or Dragon / Shapeshifter (Dark) next to
; the mage, on a square of our colour
ai_eval_revive:
        ldx side
        lda l_ai_mage,x
        ldx #80
-       cmp board,x
        beq +
        dex
        bpl -
        bra _no
+       stx mage_sq
        ldx #80
_sq:    txa
        jsr in_charmed
        bcs _next
        lda board,x
        bpl _next
        txa
        jsr is_power_point
        bcs _next
        txa
        jsr ai_favour
        cmp #4
        bcs _found
_next:  dex
        bpl _sq
_no:    clc
        rts
_found: stx sp_b
        ldy side
        ldx l_revive_a,y
        lda slot_hp,x
        beq +
        ldx l_revive_b,y
        lda slot_hp,x
        bne _no
+       lda slot_type,x
        sta sp_a
        sec
        rts
l_revive_a:     .byte 6, 29             ; Djinni, Dragon
l_revive_b:     .byte 10, 25            ; Phoenix, Shapeshifter

; Heal (S799E): the mage or a strong icon below 6 life, off the power points
ai_eval_heal:
        ldx side
        lda l_heal_lo,x
        sta str_ptr
        lda l_heal_hi,x
        sta str_ptr+1
        ldy #0
_one:   lda (str_ptr),y
        bmi _no
        tax
        lda slot_hp,x
        beq _next
        cmp #6
        bcs _next
        txa                             ; its square
        ldx #80
-       cmp board,x
        beq +
        dex
        bpl -
        bra _next
+       stx sp_a
        txa
        jsr is_power_point
        bcs _next
        sec
        rts
_next:  iny
        bra _one
_no:    clc
        rts
l_heal_lo:      .byte <l_heal_light, <l_heal_dark
l_heal_hi:      .byte >l_heal_light, >l_heal_dark
l_heal_light:   .byte SLOT_WIZARD, 6, 10, $ff
l_heal_dark:    .byte SLOT_SORCERESS, 29, $ff

; carry set when the cycle is moving toward our colour (light for Light)
l_ai_heading_ours:
        lda lum_dir
        cmp side
        bne +
        sec
        rts
+       clc
        rts
; while the cycle heads away from us: enough time left before it frees the target
l_ai_lum_ok_against:
        lda lum_level
        ldx side
        bne +
        cmp #2                          ; Light: at least blue... (lum >= 4 of 0-14)
        bcs _ok
        clc
        rts
+       cmp #4                          ; Dark: below cyan (lum < 12)
        bcc _ok
        clc
        rts
_ok:    sec
        rts
; A = spell: carry set when we have used it / the enemy has
l_ai_own_spent:
        sta tmp2
        jsr l_spell_base
        txa
        clc
        adc tmp2
        tax
        lda spell_used,x
        cmp #1
        rts
l_ai_enemy_spent:
        sta tmp2
        lda #NSPELLS                    ; the enemy's spells: Dark's at 7, Light's at 0
        ldx side
        beq +
        lda #0
+       clc
        adc tmp2
        tax
        lda spell_used,x
        cmp #1
        rts

; intruder (S75BC): the strongest enemy icon in rows 2-6 of our half (not their
; Knights / Goblins), chosen only sometimes. A = square, carry set if found.
ai_intruder:
        lda #0
        sta l_in_n
        sta l_in_best
        lda #$ff
        sta l_in_sq
        ldx side
        lda l_half_c0,x
        sta tmp2
        ldy #2 * 9
_sq:    tya
        jsr sq_rowcol
        cpx tmp2
        bcc _next
        txa
        sec
        sbc tmp2
        cmp #4
        bcs _next
        tya
        pha
        jsr enemy_at
        pla
        tay
        bcs _next
        lda slot_type,x
        and #7
        cmp #7
        beq _next                       ; Knight / Goblin
        inc l_in_n
        phx
        lda slot_type,x
        tax
        lda type_life,x
        plx
        cmp l_in_best
        bcc _next
        sta l_in_best
        sty l_in_sq
_next:  iny
        cpy #7 * 9
        bne _sq
        lda l_in_sq
        cmp #$ff
        beq _no
        jsr rand                        ; give up when n - 1 < rand & 3
        and #3
        sta tmp0
        lda l_in_n
        dec a
        cmp tmp0
        bcc _no
        lda l_in_sq
        sec
        rts
_no:    clc
        rts
l_in_n:         .byte 0
l_in_best:      .byte 0
l_in_sq:        .byte 0
l_half_c0:      .byte 0, 5

; strong_on_bad_square (S7662): 1 in 4, their Dragon / Shapeshifter (or Djinni /
; Phoenix) standing on our colour. A = square, carry set if found.
ai_strong_on_bad:
        jsr rand
        and #3
        bne _no
        ldx side
        lda l_strong_a,x
        jsr _test
        bcs _yes
        ldx side
        lda l_strong_b,x
        jsr _test
        bcs _yes
_no:    clc
        rts
_yes:   rts
_test:  sta tmp1
        tax
        lda slot_hp,x
        beq _no
        ldx #80
-       lda board,x
        cmp tmp1
        beq +
        dex
        bpl -
        bra _no
+       txa
        jsr is_power_point
        bcs _no
        lda square_kind,x
        cmp #2
        beq +                           ; any luminance square will do
        txa
        jsr ai_favour
        cmp #4
        bcc _no
+       txa
        sec
        rts
l_strong_a:     .byte 29, 6
l_strong_b:     .byte 25, 10

; Teleport: sp_a = our icon, sp_b = the target square
ai_do_teleport:
        lda #FX_TELEPORT                ; it vanishes in a spiral of sparks
        ldx sp_a
        jsr fx_on_wait
        ldx sp_a
        lda board,x
        sta pick_slot
        lda #EMPTY
        sta board,x
        lda sp_b
        sta cur_sq
        lda #MODE_TELEPORT
        sta move_mode
        jmp ai_drop

; Summon: an elemental flies in at sp_b
ai_do_summon:
        jsr summon_choose
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
        lda l_elem_entry,x
        sta cur_sq
        sta origin_sq
        jsr held_from_panel
        jsr fx_summon_burst
        jsr held_to_square
        lda sp_b
        sta ai_dest
        lda #MODE_FLY
        sta move_mode
-       lda cur_sq
        cmp ai_dest
        beq +
        jsr l_ai_toward
        jsr l_ai_step_to
        bra -
+       jmp ai_drop

;=======================================================================================
; combat (S9AE3)
;=======================================================================================
ai_delay:       .fill 2                 ; reaction delay per fighter
ai_delay_cnt:   .fill 2
ai_aim:         .fill 2                 ; stick bits to fire with
ai_move:        .fill 2                 ; committed move: stick bits
ai_move_cnt:    .fill 2                 ;   frames left
ai_range_f:     .fill 2
ai_keep_f:      .fill 2
ai_lane_f:      .fill 2
AI_MOVE_FRAMES  = 8

ai_combat_start:
        ldx #1
_f:     ldy f_type,x
        lda ai_range,y
        sta ai_range_f,x
        txa
        eor #1
        tay
        lda f_type,y
        tay
        lda ai_keepaway,y
        sta ai_keep_f,x
        lda ai_lane,y
        sta ai_lane_f,x
        lda ai_range_f,x                ; melee icons don't run far
        cmp #$10
        bcs +
        lda ai_keep_f,x
        cmp #$14
        bcc +
        lda #$14
        sta ai_keep_f,x
+       ; reaction delay: 3 (0 on a power point) + own living - enemy living, at least 1
        lda #3
        sta tmp0
        lda combat_square
        jsr is_power_point
        bcc +
        lda #0
        sta tmp0
+       txa
        tay
        lda living,y
        clc
        adc tmp0
        sta tmp0
        tya
        eor #1
        tay
        lda tmp0
        sec
        sbc living,y
        beq _one
        bpl +
_one:   lda #1
+       sta ai_delay,x
        lda #0
        sta ai_delay_cnt,x
        sta ai_aim,x
        sta ai_move,x
        sta ai_move_cnt,x
        dex
        bpl _f
        rts

; X = fighter -> f_stick,x
ai_combat:
        lda #0
        sta f_stick,x
        lda f_hp,x
        bne +
        rts
+       txa
        eor #1
        tay
        sty l_ai_foe
        ; 1. a pending shot: stand still for the reaction delay, then fire
        lda ai_aim,x
        beq _move
        lda f_kind,x
        cmp #ATK_AREA
        beq _fire
        lda ai_delay_cnt,x
        beq _fire
        dec ai_delay_cnt,x
        rts
_fire:  lda ai_aim,x
        ora #JOY_FIRE
        sta f_stick,x
        lda #0
        sta ai_aim,x
        lda ai_delay,x                  ; and freeze a little after the shot
        sta ai_delay_cnt,x
        rts
_move:  lda ai_delay_cnt,x              ; still recovering from a shot
        beq +
        dec ai_delay_cnt,x
        rts
+       ; 2. a committed move goes on
        lda ai_move_cnt,x
        beq _think
        dec ai_move_cnt,x
        lda ai_move,x
        sta f_stick,x
        rts
_think: jsr l_ai_distance
        lda ai_keep_f,x                 ; (cpy has no X-indexed mode)
        sta tmp1
        lda ai_range_f,x
        sta tmp2
        lda f_reload,x
        bne _defend
        ; 3. ready: line up a shot
        lda l_ai_dy
        cmp ai_range_f,x
        bcs _approach
        lda l_ai_dy                     ; |dy - dx| < 6: the diagonal
        sec
        sbc l_ai_dx
        bcs +
        eor #$ff
        inc a
+       cmp #6
        bcs +
        lda l_ai_hdir
        ora l_ai_vdir
        bra _aim
+       lda l_ai_dy
        cmp #9
        bcs +
        lda l_ai_dx                     ; the same row band: horizontal
        cmp ai_range_f,x
        bcs _approach
        lda l_ai_hdir
        bra _aim
+       lda l_ai_dx
        cmp #9
        bcs _approach
        lda l_ai_vdir                   ; the same column band: vertical
_aim:   sta ai_aim,x
        lda ai_delay,x
        sta ai_delay_cnt,x
        rts
_defend:
        ldy l_ai_foe
        lda m_on,y
        bne _dodge
        lda f_reload,y                  ; I'll be ready first: close in
        beq _dodge
        cmp f_reload,x
        bcs _approach
_dodge: ldy l_ai_foe
        lda m_on,y
        beq _approach
        lda ai_lane_f,x                 ; in its row lane, column lane or on a diagonal?
        clc
        adc #3
        cmp l_ai_dy
        bcs _away
        lda l_ai_dx
        cmp ai_lane_f,x
        bcc _away
        jmp ai_wander
_away:  lda f_type,x                    ; the Phoenix explodes in defence
        cmp #TYPE_PHOENIX
        bne +
        lda f_reload,x
        bne +
        lda #JOY_UP
        sta ai_aim,x
        rts
+       lda l_ai_hdir                   ; move away on both axes where it is close
        eor #JOY_LEFT | JOY_RIGHT
        ldy l_ai_dx
        cpy tmp1
        bcc +
        lda #0
+       sta tmp0
        lda l_ai_vdir
        eor #JOY_UP | JOY_DOWN
        ldy l_ai_dy
        cpy tmp1
        bcc +
        lda #0
+       ora tmp0
        beq ai_wander
        bra ai_commit
_approach:
        lda l_ai_dy
        cmp l_ai_dx
        bcs _vert
        ; mostly a horizontal offset: in range, square up vertically; else close in
        lda l_ai_dx
        cmp ai_range_f,x
        bcs +
        lda l_ai_vdir
        bra ai_commit
+       lda l_ai_hdir
        ldy l_ai_dy
        cpy tmp2
        bcc ai_commit
        ora l_ai_vdir
        bra ai_commit
_vert:  lda l_ai_dy
        cmp ai_range_f,x
        bcs +
        lda l_ai_hdir
        bra ai_commit
+       lda l_ai_vdir
        ldy l_ai_dx
        cpy tmp2
        bcc ai_commit
        ora l_ai_hdir
; A = stick bits: hold them for AI_MOVE_FRAMES. Directions blocked by a wall or a solid
; barrier are dropped (the original's move primitives refuse them); nothing left: wander.
ai_commit:
        jsr ai_allowed
        beq ai_wander
l_ai_hold:
        sta ai_move,x
        sta f_stick,x
        lda #AI_MOVE_FRAMES - 1
        sta ai_move_cnt,x
        rts
; a random move that isn't blocked (a few tries, else stand still)
ai_wander:
        lda #4
        sta l_aw_try
-       jsr rand
        and #$0f
        tay
        lda l_wander,y
        jsr ai_allowed
        bne l_ai_hold
        dec l_aw_try
        bne -
        rts
l_aw_try:       .byte 0

; X = fighter, A = stick bits -> A = those directions it can take one step in (Z set if none)
ai_allowed:
        and #$0f
        sta l_al_in
        lda #0
        sta l_al_out
        ldy #3
_dir:   lda l_al_bit,y
        and l_al_in
        beq _next
        lda f_x,x                       ; try the step, test, undo
        pha
        lda f_y,x
        pha
        lda f_x,x
        clc
        adc l_al_dx,y
        sta f_x,x
        lda f_y,x
        clc
        adc l_al_dy,y
        sta f_y,x
        lda f_x,x                       ; inside the arena?
        cmp #X_MIN
        bcc _no
        cmp #X_MAX + 1
        bcs _no
        lda f_y,x
        cmp #Y_MIN
        bcc _no
        cmp #Y_MAX + 1
        bcs _no
        phy
        jsr fighter_blocked
        ply
        bcs _no
        lda l_al_bit,y
        tsb l_al_out
_no:    pla
        sta f_y,x
        pla
        sta f_x,x
_next:  dey
        bpl _dir
        lda l_al_out
        rts
l_al_in:        .byte 0
l_al_out:       .byte 0
; up, down, left, right: a few pixels ahead, so a commitment doesn't walk into it
l_al_bit:       .byte JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT
l_al_dx:        .byte 0, 0, 256 - 4, 4
l_al_dy:        .byte 256 - 6, 6, 0, 0
l_wander:       .byte JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT, JOY_UP | JOY_LEFT, JOY_UP | JOY_RIGHT
                .byte JOY_DOWN | JOY_LEFT, JOY_DOWN | JOY_RIGHT, JOY_UP, JOY_DOWN, JOY_LEFT
                .byte JOY_RIGHT, JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT

; X = fighter -> l_ai_dx / dy (distances, units / pixels), l_ai_hdir / vdir (toward)
l_ai_distance:
        ldy l_ai_foe
        lda f_x,y
        sec
        sbc f_x,x
        ldy #JOY_RIGHT
        bcs +
        eor #$ff
        inc a
        ldy #JOY_LEFT
+       sta l_ai_dx
        sty l_ai_hdir
        ldy l_ai_foe
        lda f_y,y
        sec
        sbc f_y,x
        ldy #JOY_DOWN
        bcs +
        eor #$ff
        inc a
        ldy #JOY_UP
+       sta l_ai_dy
        sty l_ai_vdir
        rts
l_ai_foe:       .byte 0
l_ai_dx:        .byte 0
l_ai_dy:        .byte 0
l_ai_hdir:      .byte 0
l_ai_vdir:      .byte 0
