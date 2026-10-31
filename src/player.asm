;=======================================================================================
; player.asm - controls and the human player's turn on the strategy screen.
;
;   ctl_update     once a frame (frame calls it): each side's stick from its port, with
;                  the keyboard and, against the computer, both ports going to the human
;   human_turn     one whole turn for `side`: pick an icon, move it, drop it (combat), or
;                  cast a spell with a mage
;   board_stick    X = side -> A = directions pressed this frame, auto-repeating while
;                  held (joystick bits); carry set when fire was pressed
;   move_rules     X = slot -> move_mode / move_range from its type
;
; Light plays port 1, Dark port 2, as in the original.
;=======================================================================================

REPEAT_FIRST    = 14                    ; frames before a held direction repeats
REPEAT_NEXT     = 7

MODE_GROUND     = 0
MODE_FLY        = $80
MODE_TELEPORT   = $c0

stick:          .fill 2                 ; held now, per side
stick_prev:     .fill 2
stick_rep:      .fill 2                 ; auto-repeat countdown
move_mode:      .byte 0
move_range:     .byte 0
cur_sq:         .byte 0                 ; where the moving icon / frame is
path:           .fill 16                ; ground move: squares walked through
path_len:       .byte 0
pick_slot:      .byte 0
spell_move:     .byte 0                 ; 0 normal move, 1 teleport spell, $80 elemental

ctl_update:
        jsr l_dbg_script
        lda joy_port1
        sta tmp0
        lda joy_port2
        sta tmp1
        lda opt_cpu
        beq _two
        ora #0                          ; one human: everything goes to that side
        lda tmp0
        ora tmp1
        ora joy_keys
        sta tmp0
        sta tmp1
        bra _set
_two:   lda tmp0                        ; two humans: the keyboard helps Light
        ora joy_keys
        sta tmp0
_set:   lda stick
        sta stick_prev
        lda stick+1
        sta stick_prev+1
        lda tmp0
        sta stick
        lda tmp1
        sta stick+1
        rts

; test input: poke dbg_script with pairs (joystick bits, frames),
; ended by a 0 frame count, then dbg_script_on = 1. The bits go to dbg_joy frame by frame.
dbg_script:     .fill 256                ; (128 pairs; l_dbg_pos is one byte)
dbg_script_on:  .byte 0
l_dbg_pos:      .byte 0
l_dbg_left:     .byte 0
l_dbg_script:
        lda dbg_script_on
        beq _out
        lda l_dbg_left
        bne _run
        ldx l_dbg_pos                   ; the next pair
        lda dbg_script+1,x
        beq _end
        sta l_dbg_left
        lda dbg_script,x
        sta dbg_joy
        inx
        inx
        stx l_dbg_pos
_run:   dec l_dbg_left
_out:   rts
_end:   lda #0
        sta dbg_script_on
        sta dbg_joy
        sta l_dbg_pos
        rts

board_stick:
        lda stick_prev,x
        eor #$ff
        and stick,x
        and #JOY_FIRE
        cmp #JOY_FIRE                   ; carry = fire pressed
        php
        lda stick,x
        and #$0f
        beq _none
        lda stick_prev,x
        and #$0f
        bne _held
        lda #REPEAT_FIRST
        sta stick_rep,x
        bra _dir
_held:  dec stick_rep,x
        bne _none
        lda #REPEAT_NEXT
        sta stick_rep,x
_dir:   lda stick,x
        and #$0f
        plp
        ora #0                          ; Z from the directions, carry kept
        rts
_none:  lda #0
        plp
        ora #0
        rts

; X = slot -> move_mode, move_range
move_rules:
        lda slot_type,x
        tay
        lda type_move,y
        and #$c0
        sta move_mode
        lda type_move,y
        and #$3f
        sta move_range
        rts

; A = square, X = joystick bits -> A = the neighbouring square, carry set off the board.
; Diagonals are allowed (fly / teleport / cursor); ground moves pass one direction.
sq_step:
        sta tmp0
        ldy #0                          ; row
-       cmp #9
        bcc +
        sbc #9
        iny
        bra -
+       sta tmp1                        ; column
        sty tmp2
        txa
        and #JOY_UP
        beq +
        dec tmp2
+       txa
        and #JOY_DOWN
        beq +
        inc tmp2
+       txa
        and #JOY_LEFT
        beq +
        dec tmp1
+       txa
        and #JOY_RIGHT
        beq +
        inc tmp1
+       lda tmp1
        cmp #9
        bcs _off
        lda tmp2
        cmp #9
        bcs _off
        asl                             ; row * 9 + column
        asl
        asl
        adc tmp2
        adc tmp1
        clc
        rts
_off:   lda tmp0
        sec
        rts

;---------------------------------------------------------------------------------------
human_turn:
        lda side
        jsr sound_turn
        ldx side
        lda side_cursor,x
        sta cursor_sq
        lda #NO_SLOT
        sta view_msg
        sta view_msg2
_select:
        lda cursor_sq                   ; no frame (a move or spell just cleared it):
        cmp #81                         ;   back on the mage's square
        bcc +
        ldx side
        lda l_home,x
        sta cursor_sq
+       jsr frame
        lda game_result
        bne _out
        ldx side
        jsr board_stick
        php
        beq +
        tax
        lda cursor_sq
        jsr sq_step
        sta cursor_sq
+       plp
        bcc _select
        jsr try_pick
        bcs _select
        lda cur_sq                      ; next turn the frame starts where this move ended
        cmp #81
        bcc +
        ldx side
        lda l_home,x
+       ldx side
        sta side_cursor,x
_out:   lda #NO_SLOT
        sta cursor_sq
        sta origin_sq
        sta held_slot
        rts

; fire on cursor_sq: pick the icon and play the move. Carry set = start the turn again.
try_pick:
        ldx cursor_sq
        lda board,x
        bmi _no
        tax
        stx pick_slot
        jsr slot_side
        cmp side
        bne _no
        lda pick_slot
        ldx side
        cmp prisoner,x
        bne +
        lda #$14                        ; ALAS, THIS ICON IS IMPRISONED
        sta view_msg
        sec
        rts
+       ldx pick_slot
        jsr move_rules
        lda move_mode
        bne +
        lda cursor_sq
        jsr can_ground_move
        bcs +
        lda #$01                        ; ALAS, MASTER, THIS ICON CANNOT MOVE
        sta view_msg
        sec
        rts
+       ; picked: off the board, into the hand
        ldx cursor_sq
        stx origin_sq
        stx cur_sq
        lda #EMPTY
        sta board,x
        lda pick_slot
        sta held_slot
        jsr held_to_square
        ldx pick_slot
        lda slot_type,x
        clc
        adc #$1c                        ; NAME (MOVE n)
        sta view_msg
        lda #NO_SLOT
        sta view_msg2
        lda #0
        sta path_len
        jmp move_icon                   ; carry set: a ceased spell, the turn restarts
                                        ; (the mage is already back on its square)
_no:    sec
        rts

; A = square: carry set when a ground mover there has an empty or enemy neighbour
can_ground_move:
        sta tmp3
        ldx #JOY_UP
_dir:   phx
        lda tmp3
        jsr sq_step
        plx
        bcs _next
        tay
        lda board,y
        bmi _yes
        phx
        tax
        jsr slot_side
        plx
        cmp side
        bne _yes
_next:  txa
        asl
        tax
        cpx #JOY_FIRE
        bne _dir
        clc
        rts
_yes:   sec
        rts

; the held icon's drawing position = cur_sq's top-left
held_to_square:
        lda cur_sq
        jsr sq_xy
        lda box_x
        sta held_x
        lda box_x+1
        sta held_x+1
        lda box_y
        sta held_y
        rts

;---------------------------------------------------------------------------------------
; move_icon - move pick_slot from origin_sq according to move_mode / move_range until
; it is dropped. Carry set when the turn must start again (spell ceased).
move_icon:
        lda origin_sq
        sta cursor_sq
_frame: jsr frame
        lda game_result
        beq +
        clc
        rts
+       ldx side
        jsr board_stick
        php
        beq _fire
        tax
        lda move_mode
        bne _fly
        jsr ground_step
        bra _fire
_fly:   jsr fly_step
_fire:  plp
        bcc _frame
        jsr try_drop
        bcs _frame                      ; not allowed here: keep moving
        rts                             ; carry from try_drop: done (clear) / restart (set)

; X = stick bits: one orthogonal ground step, or a step back along the path
ground_step:
        txa                             ; one direction only
        and #JOY_UP | JOY_DOWN
        beq +
        txa
        and #JOY_UP | JOY_DOWN
        tax
+       lda cur_sq
        jsr sq_step
        bcs _out
        sta tmp3                        ; target
        ldx path_len
        beq +
        cmp path-1,x
        bne +
        dec path_len                    ; back along the path
        bra _move
+       ldx cur_sq                      ; standing on a foe: no further
        lda board,x
        bpl _out
        ldx tmp3
        lda board,x
        bmi _room
        tax
        jsr slot_side
        cmp side
        bne _room
        lda #$04                        ; THE SQUARE AHEAD IS OCCUPIED
        bra _msg
_room:  lda path_len
        cmp move_range
        bcc +
        lda #$03                        ; YOU HAVE MOVED YOUR LIMIT
        bra _msg
+       ldx path_len
        lda cur_sq
        sta path,x
        inc path_len
_move:  lda tmp3
        sta cur_sq
        sta cursor_sq
        jsr held_to_square
        ldx cur_sq
        lda board,x
        bmi +
        lda #$02                        ; DO YOU CHALLENGE THIS FOE?
        bra _msg
+       lda #NO_SLOT
_msg:   sta view_msg2
_out:   rts

; X = stick bits: move the frame (and a flier with it) within range of the origin
fly_step:
        lda cur_sq
        jsr sq_step
        bcs _out
        sta tmp3
        jsr sq_distance
        cmp move_range
        beq +
        bcs _out
+       lda tmp3
        sta cur_sq
        sta cursor_sq
        lda move_mode
        cmp #MODE_TELEPORT
        beq _out                        ; teleporters: only the frame moves
        jsr held_to_square
_out:   rts

; A = square -> A = Chebyshev distance from origin_sq (rows or columns, the larger)
sq_distance:
        jsr sq_rowcol
        sta tmp4                        ; row
        stx tmp4+1                      ; column
        lda origin_sq
        jsr sq_rowcol
        sec
        sbc tmp4
        bcs +
        eor #$ff
        inc a
+       sta tmp5
        txa
        sec
        sbc tmp4+1
        bcs +
        eor #$ff
        inc a
+       cmp tmp5
        bcs +
        lda tmp5
+       rts

; A = square -> A = row, X = column (an off-board origin gives row 4 and its column)
sq_rowcol:
        cmp #SQ_OFF_LEFT
        bcs _off
        ldx #0
-       cmp #9
        bcc +
        sbc #9
        inx
        bra -
+       pha
        txa
        plx
        rts
_off:   and #$0f
        tax
        lda #4
        rts
SQ_OFF_LEFT     = $f0                   ; summoned elementals start off the board
SQ_OFF_RIGHT    = $fa                   ;   ($f0 + column; columns -2 -> 0, 10 -> 10)

; fire while moving: drop on cur_sq if allowed. Carry: set = not here (keep moving),
; clear = the move is over (move_icon then returns clear), or for a ceased spell the
; turn restarts (move_icon returns with carry set through l_drop_restart)
try_drop:
        lda spell_move
        beq _normal
        ; a spell move (teleport, elemental): not onto a power point, must be a move
        lda cur_sq
        cmp origin_sq
        beq _keep
        jsr is_power_point
        bcc +
        lda #$34                        ; POWER POINTS ARE PROOF AGAINST MAGIC
        sta view_msg2
        bra _keep
+       lda spell_move
        bpl _else                       ; teleport: empty or enemy
        ldx cur_sq                      ; an elemental must attack
        lda board,x
        bmi _keep
        bra _else
_normal:
        lda cur_sq
        cmp origin_sq
        bne _else
        ; dropped where it started: a mage casts a spell, anyone else keeps moving
        ldx pick_slot
        lda slot_type,x
        cmp #TYPE_WIZARD
        beq _spell
        cmp #TYPE_SORCERESS
        bne _keep
_spell: ldx origin_sq                   ; the mage stays home while casting
        stx mage_sq
        lda pick_slot
        sta board,x
        jsr l_drop_done
        jsr cast_spell
        bcs _restart
        clc
        rts
_restart:
        pla                             ; leave move_icon too: restart the turn
        pla
        sec
        rts
_else:  ldx cur_sq
        lda board,x
        bmi _place
        tax
        jsr slot_side
        cmp side
        beq _keep
        ; an enemy: fight for the square
        lda pick_slot
        sta fight_attacker
        lda cur_sq
        sta fight_square
        jsr l_drop_done
        jsr fight_square_now
        clc
        rts
_place: lda pick_slot
        sta board,x
        lda move_mode                   ; a teleporter shimmers in
        cmp #MODE_TELEPORT
        bne +
        txa
        jsr board_teleported
+       jmp l_drop_done
_keep:  sec
        rts
l_drop_done:
        lda #NO_SLOT
        sta held_slot
        sta cursor_sq
        sta origin_sq
        sta view_msg
        sta view_msg2
        clc
        rts
