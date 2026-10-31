;=======================================================================================
; board.asm - drawing the strategy screen.
;
;   board_draw     the whole screen into the back buffer, from the game state and the
;                  view variables below (called by frame for SCENE_BOARD)
;   sq_xy          A = square -> box_x (word) / box_y = its top-left pixel
;   board_reset_cursors   cursors back to the mages' squares
;
; View variables (set by the player / AI code, read here):
;   cursor_sq      the frame being moved (NO_SLOT = none), drawn in the side's colour
;   origin_sq      the frame left on a picked icon's square (NO_SLOT = none)
;   held_slot      a picked-up icon drawn at held_x / held_y (NO_SLOT = none)
;   view_msg       message number shown at the top (NO_SLOT = none); view_msg2 a second
;   panel_list     revive list (types, $ff ends) shown in the side panel of `side`
;=======================================================================================

BOARD_X         = 52
BOARD_Y         = 22
SQ_W            = 24
SQ_H            = 19          ; (icons are 18 rows: they fit)
MSG_Y           = 1

cursor_sq:      .byte NO_SLOT
origin_sq:      .byte NO_SLOT
held_slot:      .byte NO_SLOT
held_x:         .word 0
held_y:         .byte 0
view_msg:       .byte NO_SLOT
view_msg2:      .byte NO_SLOT
panel_list:     .fill 9, $ff
panel_sel:      .byte 0
side_cursor:    .fill 2                 ; where each side's cursor last was

board_reset_cursors:
        lda #SQ_LIGHT_HOME
        sta side_cursor
        lda #SQ_DARK_HOME
        sta side_cursor+1
        lda #NO_SLOT
        sta cursor_sq
        sta origin_sq
        sta held_slot
        sta view_msg
        sta view_msg2
        rts

; draw_x0 += 1 (it is not on the base page, so no inw)
draw_x0_inc:
        inc draw_x0
        bne +
        inc draw_x0+1
+       rts

; A = square -> box_x / box_y (keeps X)
sq_xy:
        phx
        ldx #0
-       cmp #9                          ; row = A / 9, column = A mod 9
        bcc +
        sbc #9
        inx
        bra -
+       tay
        lda l_sq_y,x
        sta box_y
        lda l_sq_x_lo,y
        sta box_x
        lda l_sq_x_hi,y
        sta box_x+1
        plx
        rts
l_sq_x_lo:      .byte <(BOARD_X + range(9) * SQ_W)
l_sq_x_hi:      .byte >(BOARD_X + range(9) * SQ_W)
l_sq_y:         .byte BOARD_Y + range(9) * SQ_H

;---------------------------------------------------------------------------------------
board_draw:
        lda lum_level                   ; the squares change only with the luminance
        jsr cache_restore
        bcc +
        lda #COL_BG
        jsr fcm_clear
        jsr l_bd_frame
        jsr l_bd_squares
        jsr cache_save
+       jsr l_bd_powers
        jsr l_bd_icons
        lda origin_sq
        ldy #COL_GREY
        jsr l_bd_cursor
        lda cursor_sq
        ldx side
        ldy l_side_col,x
        jsr l_bd_cursor
        jsr l_bd_held
        jsr l_bd_panels
        jsr l_bd_message
        lda zoom_t
        bpl l_bd_zoom
        rts

; the combat zoom: a frame growing from the disputed square to the screen edges.
; Edge = start + (end - start) * zoom_t / ZOOM_STEPS, for each of the four edges.
ZOOM_STEPS      = 16
zoom_t:         .byte $ff               ; $ff = no zoom
zoom_x0:        .byte 0                 ; the square's left x / 2
zoom_y0:        .byte 0
l_bd_zoom:
        lda zoom_x0                     ; left: 2*zx -> 0
        asl
        sta l_bz_from
        lda #0
        rol
        sta l_bz_from+1
        lda #0
        sta l_bz_to
        sta l_bz_to+1
        jsr l_bz_lerp
        sta draw_x0
        stx draw_x0+1
        lda zoom_y0                     ; top: zy -> 0
        sta l_bz_from
        lda #0
        sta l_bz_from+1
        jsr l_bz_lerp
        sta draw_y0
        lda l_bz_from                   ; bottom: zy + SQ_H - 1 -> 199
        clc
        adc #SQ_H - 1
        sta l_bz_from
        lda #199
        sta l_bz_to
        jsr l_bz_lerp
        sec
        sbc draw_y0
        inc a
        sta draw_h
        lda zoom_x0                     ; right: 2*zx + SQ_W - 1 -> 319
        asl
        sta l_bz_from
        lda #0
        rol
        sta l_bz_from+1
        clc
        lda l_bz_from
        adc #SQ_W - 1
        sta l_bz_from
        bcc +
        inc l_bz_from+1
+       lda #<319
        sta l_bz_to
        lda #>319
        sta l_bz_to+1
        jsr l_bz_lerp
        clc                             ; width = right - left + 1
        sbc draw_x0
        sta draw_w
        txa
        sbc draw_x0+1
        sta draw_w+1
        clc
        lda draw_w
        adc #2
        sta draw_w
        bcc +
        inc draw_w+1
+       ldx combat_l
        lda l_wall_col,x
        sta draw_col
        jsr draw_rect
        clc                             ; and a second frame inside it
        lda draw_x0
        adc #1
        sta draw_x0
        bcc +
        inc draw_x0+1
+       inc draw_y0
        sec
        lda draw_w
        sbc #2
        sta draw_w
        bcs +
        dec draw_w+1
+       dec draw_h
        dec draw_h
        jmp draw_rect
l_bz_from:      .word 0
l_bz_to:        .word 0
; A/X = from + (to - from) * zoom_t / ZOOM_STEPS (signed 16-bit difference)
l_bz_lerp:
        sec
        lda l_bz_to
        sbc l_bz_from
        sta tmp4
        lda l_bz_to+1
        sbc l_bz_from+1
        sta tmp4+1
        php                             ; negative difference: work with its size
        bpl +
        lda #0
        sec
        sbc tmp4
        sta tmp4
        lda #0
        sbc tmp4+1
        sta tmp4+1
+       lda zoom_t
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16                       ; MULTOUT = |diff| * t
        lda MULTOUT                     ; / 16
        sta tmp4
        lda MULTOUT+1
        sta tmp4+1
        ldx #4
-       lsr tmp4+1
        ror tmp4
        dex
        bne -
        plp
        bpl +
        sec
        lda l_bz_from
        sbc tmp4
        pha
        lda l_bz_from+1
        sbc tmp4+1
        tax
        pla
        rts
+       clc
        lda l_bz_from
        adc tmp4
        pha
        lda l_bz_from+1
        adc tmp4+1
        tax
        pla
        rts
l_side_col:     .byte COL_LIGHT_SIDE, COL_DARK_SIDE

; a bevelled gold frame around the board
l_bd_frame:
        lda #<(BOARD_X - 4)
        sta box_x
        lda #>(BOARD_X - 4)
        sta box_x+1
        lda #BOARD_Y - 3
        sta box_y
        lda #9 * SQ_W + 8
        sta box_w
        lda #9 * SQ_H + 6
        sta box_h
        lda #COL_FRAME_LO
        jsr box
        lda #<(BOARD_X - 3)
        sta box_x
        lda #BOARD_Y - 2
        sta box_y
        lda #9 * SQ_W + 5
        sta box_w
        lda #9 * SQ_H + 4
        sta box_h
        lda #COL_FRAME_HI
        jsr box
        lda #<(BOARD_X - 2)
        sta box_x
        lda #BOARD_Y - 1
        sta box_y
        lda #9 * SQ_W + 3
        sta box_w
        lda #9 * SQ_H + 2
        sta box_h
        lda #COL_FRAME
        jmp box

; the 81 squares, bevelled: base, light top/left edge, dark bottom/right edge
l_bd_squares:
        lda #80
        sta l_bd_sq
_next:  lda l_bd_sq
        tax
        lda square_kind,x
        beq _dark
        cmp #1
        beq _light
        lda lum_level
        bra _col
_dark:  lda #0
        bra _col
_light: lda #LUM_LEVELS - 1
_col:   asl                             ; 4 shades per level
        asl
        clc
        adc #LUM_BASE
        sta l_bd_col
        lda l_bd_sq
        jsr sq_xy
        lda #SQ_W
        sta box_w
        lda #SQ_H
        sta box_h
        lda l_bd_col
        jsr box
        ; light edge: top row and left column
        lda l_bd_col
        inc a
        sta draw_col
        lda #SQ_W
        sta draw_w
        lda #0
        sta draw_w+1
        jsr draw_hline
        lda #SQ_H
        sta draw_h
        jsr draw_vline
        ; dark edge: bottom row and right column
        lda l_bd_col
        clc
        adc #2
        sta draw_col
        lda draw_y0
        clc
        adc #SQ_H - 1
        sta draw_y0
        jsr draw_x0_inc
        lda #SQ_W - 1
        sta draw_w
        jsr draw_hline
        lda box_y
        inc a
        sta draw_y0
        clc
        lda box_x
        adc #SQ_W - 1
        sta draw_x0
        lda box_x+1
        adc #0
        sta draw_x0+1
        lda #SQ_H - 1
        sta draw_h
        jsr draw_vline
        dec l_bd_sq
        bmi +
        jmp _next
+       rts

; empty power points show their flashing symbol
l_bd_powers:
        lda frame_count
        and #$20
        bne _out
        ldy #4
-       ldx pp_square,y
        lda board,x
        bpl +
        phy
        txa
        ldx #SPR_POWER
        jsr l_bd_sprite
        ply
+       dey
        bpl -
_out:   rts
l_bd_sq:        .byte 0
l_bd_col:       .byte 0

; every icon on the board; the imprisoned ones get chains
l_bd_icons:
        lda flash_t                     ; a teleport's shimmer runs down
        beq +
        dec flash_t
+       lda #80
        sta l_bd_sq
_next:  ldx l_bd_sq
        lda board,x
        bmi _skip
        cpx flash_sq                    ; a teleported icon shimmers in
        bne +
        lda flash_t
        and #2
        bne _skip
        lda board,x
+       tax
        lda slot_type,x
        clc
        adc #SPR_ICON
        tax
        lda l_bd_sq
        jsr l_bd_sprite
        ldx l_bd_sq
        lda board,x
        cmp prisoner
        beq _chain
        cmp prisoner+1
        bne _skip
_chain: lda l_bd_sq
        ldx #SPR_CHAINS
        jsr l_bd_sprite
_skip:  dec l_bd_sq
        bpl _next
        rts

; A = square: the icon arriving there by teleport shimmers for a moment, in a spiral of
; sparks coming down (the departure's, backwards)
FLASH_FRAMES    = 28
flash_sq:       .byte NO_SLOT
flash_t:        .byte 0
board_teleported:
        sta flash_sq
        lda #FLASH_FRAMES
        sta flash_t
        lda #FXF_BACKWARDS
        sta fx_flags
        ldx flash_sq
        lda #FX_TELEPORT
        jmp fx_on

; the held icon (an elemental) starts in the side panel beside row 4, then glides on
; when held_to_square sets its square
held_from_panel:
        ldx side
        lda l_panel_x,x
        sta held_x
        lda l_panel_x_hi,x
        sta held_x+1
        lda #BOARD_Y + 4 * SQ_H
        sta held_y
        jmp frame                       ; (one frame there: the glide starts from it)

; A = square, X = sprite: draw it on that square
l_bd_sprite:
        stx bs_id
        jsr sq_xy
        lda box_x
        sta bs_x
        lda box_x+1
        sta bs_x+1
        lda box_y
        sta bs_y
        lda #0
        sta bs_y+1
        jmp blit_sprite

; A = square (NO_SLOT = none), Y = colour: a two-pixel frame around it
l_bd_cursor:
        cmp #81                         ; none, or off the board (an elemental's origin)
        bcs +
        sty draw_col
        jsr sq_xy
        lda box_x
        sta draw_x0
        lda box_x+1
        sta draw_x0+1
        lda box_y
        sta draw_y0
        lda #SQ_W
        sta draw_w
        lda #0
        sta draw_w+1
        lda #SQ_H
        sta draw_h
        jsr draw_rect
        jsr draw_x0_inc
        inc draw_y0
        lda #SQ_W - 2
        sta draw_w
        lda #SQ_H - 2
        sta draw_h
        jmp draw_rect
+       rts

; the picked-up icon at held_x / held_y
; It glides: the drawn position (glide_x / glide_y) follows held_x / held_y GLIDE_STEP
; pixels a frame, with the icon's walking sound on voice 1 while it moves. While moving
; it walks: its combat set is copied into fighter 0's ids when it is picked up, and the
; walk cycle for its direction is drawn. Standing still, it is its board icon.
GLIDE_STEP      = 3
WALK_RAISE      = 2                     ; combat frames stand 2 rows lower than icons
glide_x:        .word 0
glide_y:        .byte 0
l_glide_slot:   .byte NO_SLOT           ; the icon being glided
l_gl_walk:      .byte FR_RIGHT          ; first frame of the walk cycle it is in
l_gl_anim:      .byte 0                 ; frames walked
l_bd_held:
        ldx held_slot
        cpx #NO_SLOT
        bne +
        stx l_glide_slot
        ldx #0
        jmp sound_walk_stop
+       cpx l_glide_slot
        beq _step
        stx l_glide_slot                ; just picked up: it starts where it is
        lda held_x
        sta glide_x
        lda held_x+1
        sta glide_x+1
        lda held_y
        sta glide_y
        lda slot_type,x
        jsr load_walk_set
_step:  ; facing: the way it still has to go, sideways first
        sec
        lda held_x
        sbc glide_x
        tay
        lda held_x+1
        sbc glide_x+1
        bmi _face_l
        bne _face_r
        cpy #0
        beq _face_y
_face_r:
        lda #FR_RIGHT
        bra _face
_face_l:
        lda #FR_LEFT
        bra _face
_face_y:
        lda held_y
        cmp glide_y
        beq _faced
        lda #FR_DOWN
        bcs _face
        lda #FR_UP
_face:  sta l_gl_walk
_faced: lda #0
        sta l_gl_moved
        ; x (16-bit): GLIDE_STEP toward held_x, or the rest of the way
        sec
        lda held_x
        sbc glide_x
        sta tmp4
        lda held_x+1
        sbc glide_x+1
        sta tmp4+1
        ora tmp4
        beq _y
        inc l_gl_moved
        lda tmp4+1
        bmi _left
        bne _right
        lda tmp4
        cmp #GLIDE_STEP
        bcc _xsnap
_right: clc
        lda glide_x
        adc #GLIDE_STEP
        sta glide_x
        bcc _y
        inc glide_x+1
        bra _y
_left:  lda tmp4
        cmp #256 - GLIDE_STEP + 1
        bcs _xsnap
        sec
        lda glide_x
        sbc #GLIDE_STEP
        sta glide_x
        bcs _y
        dec glide_x+1
        bra _y
_xsnap: lda held_x
        sta glide_x
        lda held_x+1
        sta glide_x+1
_y:     lda held_y
        sec
        sbc glide_y
        beq _draw
        inc l_gl_moved
        bcc _up
        cmp #GLIDE_STEP
        bcc _ysnap
        lda glide_y
        clc
        adc #GLIDE_STEP
        sta glide_y
        bra _draw
_up:    cmp #256 - GLIDE_STEP + 1
        bcs _ysnap
        lda glide_y
        sec
        sbc #GLIDE_STEP
        sta glide_y
        bra _draw
_ysnap: lda held_y
        sta glide_y
_draw:  ldx held_slot
        lda slot_type,x
        pha
        clc
        adc #SPR_ICON
        sta bs_id
        lda glide_y
        sta bs_y
        lda l_gl_moved
        beq _still
        inc l_gl_anim                   ; walking: a new frame every 2
        lda l_gl_anim
        lsr
        and #3
        clc
        adc l_gl_walk
        adc #FIGHTER_SPR
        sta bs_id
        lda glide_y
        sec
        sbc #WALK_RAISE
        sta bs_y
_still: lda glide_x
        sta bs_x
        lda glide_x+1
        sta bs_x+1
        lda #0
        sta bs_y+1
        jsr blit_sprite
        pla
        ldx #0
        ldy l_gl_moved
        beq +
        jmp sound_walk_type
+       jmp sound_walk_stop
l_gl_moved:     .byte 0

; side panels: the side names (the one to move lit) and the revive list
l_bd_panels:
        lda #24
        sta ftext_y
        lda #COL_SHADOW
        sta ftext_shadow
        ldx #SIDE_LIGHT
        jsr l_bd_name
        ldx #SIDE_DARK
        jsr l_bd_name
        lda panel_list
        bmi _out
        ; up to 8 icons in a column beside the board, the selected one framed
        ldx side
        lda l_panel_x,x
        sta l_pn_x
        lda l_panel_x_hi,x
        sta l_pn_x+1
        lda #0
        sta l_pn_i
        lda #BOARD_Y + 18
        sta l_pn_y
_icon:  ldx l_pn_i
        lda panel_list,x
        bmi _out
        clc
        adc #SPR_ICON
        sta bs_id
        lda l_pn_x
        sta bs_x
        lda l_pn_x+1
        sta bs_x+1
        lda #0
        sta bs_y+1
        lda l_pn_y
        sta bs_y
        jsr blit_sprite
        lda l_pn_i
        cmp panel_sel
        bne +
        ldx side
        lda l_side_col,x
        sta draw_col
        lda l_pn_x
        sta draw_x0
        lda l_pn_x+1
        sta draw_x0+1
        lda #0
        sta draw_w+1
        lda l_pn_y
        sta draw_y0
        lda #SQ_W
        sta draw_w
        lda #SQ_H
        sta draw_h
        jsr draw_rect
+       lda l_pn_y
        clc
        adc #SQ_H
        sta l_pn_y
        inc l_pn_i
        bra _icon
_out:   rts
l_panel_x:      .byte 14, <(BOARD_X + 9 * SQ_W + 18)
l_panel_x_hi:   .byte 0, >(BOARD_X + 9 * SQ_W + 18)
l_pn_x:         .word 0
l_pn_y:         .byte 0
l_pn_i:         .byte 0

; X = side: its name above its panel, bright when it is to move
l_bd_name:
        lda l_name_x,x
        sta ftext_x
        lda l_name_x_hi,x
        sta ftext_x+1
        lda #COL_DIM
        cpx side
        bne +
        lda l_side_col,x
+       sta ftext_col
        lda l_name_lo,x
        pha
        lda l_name_hi,x
        tax
        pla
        jmp ftext_draw
l_name_x:       .byte 6, <(BOARD_X + 9 * SQ_W + 10)
l_name_x_hi:    .byte 0, >(BOARD_X + 9 * SQ_W + 10)
l_name_lo:      .byte <str_light, <str_dark
l_name_hi:      .byte >str_light, >str_dark
str_light:      .null "LIGHT"
str_dark:       .null "DARK"

; the message line(s) at the top, centred
l_bd_message:
        lda #MSG_Y
        sta ftext_y
        lda #COL_TEXT
        sta ftext_col
        lda #COL_SHADOW
        sta ftext_shadow
        ldx view_msg
        cpx #NO_SLOT
        beq +
        lda msg_lo,x
        pha
        lda msg_hi,x
        tax
        pla
        jsr ftext_centre
        lda #MSG_Y + FTEXT_LINE_H
        sta ftext_y
        ldx view_msg2
        cpx #NO_SLOT
        beq +
        lda msg_lo,x
        pha
        lda msg_hi,x
        tax
        pla
        jmp ftext_centre
+       rts
