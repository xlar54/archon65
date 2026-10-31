;=======================================================================================
; combat.asm - the combat arena.
;
;   combat_run     fight combat_slot[0] (Light) against combat_slot[1] (Dark) for
;                  combat_square; returns combat_hp[] (0 = dead) and the board scene
;   arena_draw     the scene (SCENE_ARENA)
;
; Coordinates are the original's: x in 2-pixel units (screen x = 2x), y in pixels.
; A fighter's sprite is 24 x 18 with its top-left at (2x, y). Fighter f = side f.
; Each fighter's sprites (a combat set from attic) live at sprite ids
; FIGHTER_SPR + f * 32: 24 animation frames, then 7 missile images.
;=======================================================================================

FIGHTER_SPR     = 192
X_MIN           = 8                     ; icon limits ($7F01)
X_MAX           = 145
Y_MIN           = 18
Y_MAX           = 174
MX_MIN          = 2                     ; a missile ends outside these
MX_MAX          = 154
MY_MIN          = 10
MY_MAX          = 189
CYCLE_FRAMES    = 213                   ; barrier colour step: 256 jiffies of 60 Hz
END_FRAMES      = 65                    ; after a death, before the arena closes
MELEE_FRAMES    = 15
PHOENIX_FRAMES  = 50
BANSHEE_FRAMES  = 41
POSE_FRAMES     = 10                    ; a missile thrower shows its attack pose

; frames of a combat set
FR_RIGHT        = 0
FR_DOWN         = 4
FR_UP           = 8
FR_LEFT         = 17
FR_MISSILE      = 24

ATK_MELEE       = $20
ATK_AREA        = $40
ATK_COPY        = $80
TYPE_PHOENIX    = 6
TYPE_BANSHEE    = 14

combat_slot:    .fill 2
combat_square:  .byte 0
combat_hp:      .fill 2
combat_l:       .byte 0                 ; the square's luminance 0..7

; ---- fighters (index = side) ----
f_type:         .fill 2                 ; type as fought (a Shapeshifter copies)
f_hp:           .fill 2
f_x:            .fill 2
f_y:            .fill 2
f_frame:        .fill 2                 ; frame of the set shown
f_walk:         .fill 2                 ; walk animation counter
f_dir:          .fill 2                 ; facing: joystick bits of the last move
f_reload:       .fill 2
f_force:        .fill 2
f_kind:         .fill 2                 ; type_attack
f_slow:         .fill 2
f_pose:         .fill 2                 ; attack pose countdown
f_hurt:         .fill 2                 ; hit flash countdown
f_stick:        .fill 2                 ; this frame's controls
; ---- attacks ----
m_on:           .fill 2                 ; 0 none, else frames left (missiles: 1)
m_x:            .fill 2
m_y:            .fill 2
m_dx:           .fill 2                 ; signed per frame
m_dy:           .fill 2
m_spr:          .fill 2
m_hit:          .fill 2                 ; melee: already hit
end_timer:      .byte 0
cycle_timer:    .byte 0
cmb_frame:      .byte 0

; ---- barriers: an 8 x 6 grid of cells, each empty ($ff) or in group 0-2 ----
BAR_COLS        = 8
BAR_ROWS        = 6
BAR_RISE        = 4                     ; a pillar's top rises this far above its box
bar_cell:       .fill BAR_COLS * BAR_ROWS
grp_lum:        .fill 3                 ; 0..7
grp_dir:        .fill 3                 ; 0 up, 1 down
bar_version:    .byte 0                 ; changes with the barriers (background cache key)
BAR_OPEN        = 0
BAR_FUZZY       = 1
BAR_SOLID       = 2

;---------------------------------------------------------------------------------------
combat_run:
        lda combat_square
        jsr square_lum
        sta combat_l
        jsr arena_zoom
        jsr combat_setup
        lda #SCENE_ARENA
        sta scene
        lda #0
        sta paused
_loop:  jsr frame
        lda game_result
        bne _out                        ; quit
        lda paused
        beq +
        lda opt_cpu                     ; pause only against the computer
        bne _loop
        sta paused
+       jsr combat_frame
        lda end_timer
        beq _loop
        dec end_timer
        bne _loop
        lda m_on                        ; wait for attacks still in flight
        ora m_on+1
        beq _out
        inc end_timer
        bra _loop
_out:   lda f_hp
        sta combat_hp
        lda f_hp+1
        sta combat_hp+1
        jsr sound_off
        lda #SCENE_BOARD
        sta scene
        rts

;---------------------------------------------------------------------------------------
; the disputed square grows to fill the screen (on the board scene)
arena_zoom:
        lda combat_square
        jsr sq_xy
        lda box_x                       ; zoom from the square (x / 2 to stay in a byte)
        lsr box_x+1
        ror a
        sta zoom_x0
        lda box_y
        sta zoom_y0
        lda #0
        sta zoom_t
        jsr sound_zoom
-       jsr frame
        inc zoom_t
        lda zoom_t
        cmp #ZOOM_STEPS
        bne -
        lda #$ff
        sta zoom_t
        rts

;---------------------------------------------------------------------------------------
combat_setup:
        ldx #1
_side:  ldy combat_slot,x
        lda slot_type,y
        sta f_type,x
        lda slot_hp,y
        sta f_hp,x
        dex
        bpl _side
        ; the Shapeshifter becomes its foe (as Dark, its foe is Light)
        lda f_type+1
        cmp #TYPE_SHIFTER
        bne +
        lda f_type
        sta f_type+1
+       ; lifespans: stored + the luminance bonus, minus spells cast on the home PP
        ldx #1
_hp:    ldy combat_slot,x
        cpy #SLOT_ELEM
        bcc +
        ldy f_type,x                    ; an elemental: full lifespan, no bonus
        lda type_life,y
        sta f_hp,x
        bra _next
+       lda slot_type,y
        cmp #TYPE_SHIFTER
        bne +
        ldy f_type,x                    ; the copy's lifespan (its own 10 against elementals)
        lda type_life,y
        cpy #16
        bcc _sh
        lda #10
_sh:    sta f_hp,x
+       lda combat_l                    ; Light + L, Dark + 7 - L
        cpx #SIDE_DARK
        bne +
        eor #7
+       clc
        adc f_hp,x
        sta f_hp,x
        lda combat_square
        cmp l_home,x
        bne _next
        lda f_hp,x
        sec
        sbc spells_cast,x
        beq _min
        bcs +
_min:   lda #1
+       sta f_hp,x
_next:  dex
        bpl _hp
        ; stats, places, sprite sets
        ldx #1
_stats: ldy f_type,x
        lda type_force,y
        sta f_force,x
        lda type_attack,y
        sta f_kind,x
        lda type_slow,y
        sta f_slow,x
        lda #0
        sta f_reload,x
        sta f_walk,x
        sta f_pose,x
        sta f_hurt,x
        sta m_on,x
        lda l_fight_x,x
        sta f_x,x
        lda l_fight_y,x
        sta f_y,x
        lda l_fight_dir,x
        sta f_dir,x
        lda l_fight_frame,x
        sta f_frame,x
        phx
        jsr load_combat_set
        plx
        dex
        bpl _stats
        lda #0
        sta end_timer
        sta cmb_frame
        lda #CYCLE_FRAMES
        sta cycle_timer
        inc bar_version                 ; a new arena: the cached picture is stale
        jsr place_barriers
        jmp ai_combat_start
l_home:         .byte SQ_LIGHT_HOME, SQ_DARK_HOME
l_fight_x:      .byte X_MIN, X_MAX
l_fight_y:      .byte $58, $68
l_fight_dir:    .byte JOY_RIGHT, JOY_LEFT
l_fight_frame:  .byte FR_RIGHT, FR_LEFT

; X = fighter: DMA its combat set (= its type as fought) from attic into its sprite
; ids, with the boxes. A Shapeshifter's copy is then recoloured in its own hue.
load_combat_set:
        phx
        jsr l_lcs_copy
        plx
        cpx #SIDE_DARK
        bne +
        ldy combat_slot+1
        lda slot_type,y
        cmp #TYPE_SHIFTER
        bne +
        jmp tint_shifter
+       rts

; A = type: its combat set into fighter 0's sprite ids, for the board's walking icon
load_walk_set:
        sta f_type
        ldx #0
        jmp l_lcs_copy

l_lcs_copy:
        lda f_type,x
        ; ptr1 = ATTIC_COMBAT + set * $4000
        sta tmp0
        lda #0
        sta ptr1
        lda tmp0                        ; address bits 14-15: set & 3
        and #3
        lsr
        ror
        ror
        sta ptr1+1
        lda tmp0                        ; bits 16-19: set >> 2
        lsr
        lsr
        clc
        adc #`ATTIC_COMBAT
        sta ptr1+2
        lda #ATTIC_COMBAT >> 24
        sta ptr1+3
        ; ptr2 = SPR_BASE + (FIGHTER_SPR + f * 32) * 512
        lda #0
        sta ptr2
        sta ptr2+3
        lda l_set_dst_hi,x
        sta ptr2+1
        lda #`(SPR_BASE + FIGHTER_SPR * 512)
        sta ptr2+2
        lda #<(COMBAT_SET_SPRITES * 512)
        sta tmp5
        lda #>(COMBAT_SET_SPRITES * 512)
        sta tmp5+1
        phx
        jsr dma_copy_far
        ; the boxes follow the sprites: 4 x 32 bytes -> set_boxes. (dma_copy_far only
        ; moves the pointers when it splits a copy, so step ptr1 here.)
        clc
        lda ptr1+1
        adc #>(COMBAT_SET_SPRITES * 512)
        sta ptr1+1
        lda ptr1+2
        adc #0
        sta ptr1+2
        lda #<set_boxes
        sta ptr2
        lda #>set_boxes
        sta ptr2+1
        lda #0
        sta ptr2+2
        sta ptr2+3
        lda #128
        sta tmp5
        lda #0
        sta tmp5+1
        jsr dma_copy_far
        plx
        lda l_set_id,x
        tay
        ldx #0
-       lda set_boxes,x
        sta spr_x0,y
        lda set_boxes+32,x
        sta spr_x1,y
        lda set_boxes+64,x
        sta spr_y0,y
        lda set_boxes+96,x
        sta spr_y1,y
        iny
        inx
        cpx #COMBAT_SET_SPRITES
        bne -
        rts
; the Dark fighter's sprites through shifter_lut (src/gen/sprites.asm)
tint_shifter:
        lda #0
        sta ptr0
        sta ptr0+3
        lda l_set_dst_hi+1
        sta ptr0+1
        lda #`(SPR_BASE + FIGHTER_SPR * 512)
        sta ptr0+2
        lda #<(COMBAT_SET_SPRITES * 512)
        sta tmp6
        lda #>(COMBAT_SET_SPRITES * 512)
        sta tmp6+1
        ldz #0
-       lda [ptr0],z
        tax
        lda shifter_lut,x
        sta [ptr0],z
        inw ptr0
        dew tmp6
        lda tmp6
        ora tmp6+1
        bne -
        rts

l_set_dst_hi:   .byte >(SPR_BASE + FIGHTER_SPR * 512), >(SPR_BASE + (FIGHTER_SPR + 32) * 512)
l_set_id:       .byte FIGHTER_SPR, FIGHTER_SPR + 32
set_boxes:      .fill 128
        .cerror ((SPR_BASE + FIGHTER_SPR * 512) & $ffff) + 64 * 512 > $10000, "fighter sprites cross a bank"

; 3 groups of 6 barriers in random free cells; group colours start 0 up, 4 up, 5 down
place_barriers:
        ldx #BAR_COLS * BAR_ROWS - 1
        lda #$ff
-       sta bar_cell,x
        dex
        bpl -
        lda #3 * 6 - 1
        sta l_pb_n
_one:   jsr rand
        and #63
        cmp #BAR_COLS * BAR_ROWS
        bcs _one
        tax
        lda bar_cell,x
        bpl _one                        ; taken: try another cell
        lda l_pb_n                      ; group = barrier / 6
        ldy #0
-       cmp #6
        bcc +
        sbc #6
        iny
        bra -
+       tya
        sta bar_cell,x
        dec l_pb_n
        bpl _one
        ldx #2
-       lda l_grp_lum,x
        sta grp_lum,x
        lda l_grp_dir,x
        sta grp_dir,x
        dex
        bpl -
        rts
l_pb_n:         .byte 0
l_grp_lum:      .byte 0, 4, 5
l_grp_dir:      .byte 0, 0, 1

; A = group -> A = BAR_OPEN / BAR_FUZZY / BAR_SOLID (keeps X, Y)
group_state:
        phx
        tax
        lda grp_lum,x
        plx
        cmp #2
        bcc +
        lda #BAR_SOLID
+       rts

;---------------------------------------------------------------------------------------
; one frame of combat
combat_frame:
        inc cmb_frame
        jsr step_barriers
        ldx #1
_f:     phx
        jsr fighter_controls
        plx
        phx
        jsr fighter_update
        plx
        phx
        jsr attack_update
        plx
        dex
        bpl _f
        rts

step_barriers:
        dec cycle_timer
        bne _out
        lda #CYCLE_FRAMES
        sta cycle_timer
        inc bar_version
        ldx #2
_g:     lda grp_dir,x
        bne _down
        inc grp_lum,x
        lda grp_lum,x
        cmp #7
        bne _next
        inc grp_dir,x
        bra _next
_down:  dec grp_lum,x
        bne _next
        lda #0
        sta grp_dir,x
_next:  dex
        bpl _g
_out:   rts

; X = fighter -> f_stick from its player or the computer
fighter_controls:
        lda opt_cpu
        and l_side_bit,x
        beq +
        jmp ai_combat                   ; sets f_stick,x
+       lda stick,x
        sta f_stick,x
        rts

;---------------------------------------------------------------------------------------
; X = fighter: reload, movement, starting an attack
fighter_update:
        lda f_hp,x
        bne +
        rts                             ; dead
+       lda f_hurt,x
        beq +
        dec f_hurt,x
+       lda f_pose,x
        beq +
        dec f_pose,x
+       lda f_reload,x
        beq +
        dec f_reload,x
        bne +
        jsr sound_ready                 ; the bell: ready to attack again
+       jsr thrown_off
        bcs _out
        lda f_stick,x
        and #JOY_FIRE
        beq _move
        jmp try_attack                  ; fire held: aim / attack, no walking
_move:  lda m_on,x                      ; Knights, Goblins and the Phoenix stand still
        beq _walk                       ;   while their attack lasts
        lda f_kind,x
        cmp #ATK_MELEE
        beq _out
        lda f_type,x
        cmp #TYPE_PHOENIX
        beq _out
_walk:  lda f_stick,x
        and #$0f
        bne +
        jmp sound_walk_stop
+       jsr sound_walk
        lda f_slow,x                    ; Golem, Troll, Earth: skip one frame in four
        beq +
        lda cmb_frame
        and #3
        cmp #3
        beq _out
+       jsr fighter_fuzzy               ; half speed on a fuzzy barrier
        bcc +
        lda cmb_frame
        lsr
        bcs _out
+       jmp walk
_out:   rts

; X = fighter: move one step by f_stick, blocked by the walls and solid barriers
walk:
        lda f_stick,x
        sta f_dir,x
        and #JOY_LEFT
        beq +
        lda f_x,x
        cmp #X_MIN + 1
        bcc +
        dec f_x,x
        jsr fighter_blocked
        bcc +
        inc f_x,x
+       lda f_stick,x
        and #JOY_RIGHT
        beq +
        lda f_x,x
        cmp #X_MAX
        bcs +
        inc f_x,x
        jsr fighter_blocked
        bcc +
        dec f_x,x
+       lda f_stick,x
        and #JOY_UP
        beq +
        lda f_y,x
        cmp #Y_MIN + 1
        bcc +
        dec f_y,x
        jsr fighter_blocked
        bcc +
        inc f_y,x
+       lda f_stick,x
        and #JOY_DOWN
        beq +
        lda f_y,x
        cmp #Y_MAX
        bcs +
        inc f_y,x
        jsr fighter_blocked
        bcc +
        dec f_y,x
+       ; walk animation: 4 frames per direction, a step every 4 frames
        inc f_walk,x
        lda f_walk,x
        lsr
        lsr
        and #3
        sta tmp0
        lda f_dir,x
        and #JOY_LEFT | JOY_RIGHT
        beq _vert
        and #JOY_LEFT
        beq +
        lda #FR_LEFT
        bra _set
+       lda #FR_RIGHT
        bra _set
_vert:  lda f_dir,x
        and #JOY_UP
        beq +
        lda #FR_UP
        bra _set
+       lda #FR_DOWN
_set:   clc
        adc tmp0
        sta f_frame,x
        rts

; X = fighter on a barrier that has become solid: thrown off. First as the original
; ($9AA2): snapped to the lanes between the barriers (x = x & $F0 | $0C, y = (y + 8) & $E0,
; inside the arena) - which can pop it through to the other side. If that spot still
; touches a solid barrier, it is pushed out, away from the barrier's centre. Carry set
; while being thrown (the fighter can't act).
thrown_off:
        jsr fighter_box
        lda #BAR_SOLID
        jsr box_on_barrier
        bcs +
        rts
+       lda f_x,x                       ; try the snap
        pha
        lda f_y,x
        pha
        lda f_x,x
        and #$f0
        ora #$0c
        cmp #X_MAX
        bcc +
        lda #X_MAX
+       sta f_x,x
        lda f_y,x
        clc
        adc #8
        and #$e0
        cmp #Y_MIN
        bcs +
        adc #$20
+       cmp #Y_MAX
        bcc +
        sbc #$20
+       sta f_y,x
        lda #0                          ; (the computer's planned move is off)
        sta ai_move_cnt,x
        jsr fighter_blocked
        bcs _undo
        pla
        pla
        sec
        rts
_undo:  pla
        sta f_y,x
        pla
        sta f_x,x
        jsr fighter_box
        lda #BAR_SOLID
        jsr box_on_barrier
        ; Y = the barrier's cell (from box_on_barrier)
        lda l_cell_ux,y                ; barrier centre x (units) = cell x + 4
        clc
        adc #4
        sec
        sbc #6
        cmp f_x,x                       ; fighter centre is f_x + 6
        bcc _right
        lda f_x,x
        cmp #X_MIN + 1
        bcc _vert
        dec f_x,x
        bra _vert
_right: lda f_x,x
        cmp #X_MAX
        bcs _vert
        inc f_x,x
_vert:  lda l_cell_y,y
        clc
        adc #8
        sec
        sbc #9
        cmp f_y,x
        bcc _down
        lda f_y,x
        cmp #Y_MIN + 2
        bcc _done
        dec f_y,x
        dec f_y,x
        bra _done
_down:  lda f_y,x
        cmp #Y_MAX - 1
        bcs _done
        inc f_y,x
        inc f_y,x
_done:  sec
        rts
_out:   clc
        rts

; X = fighter -> carry set when its box overlaps a solid barrier
fighter_blocked:
        jsr fighter_box
        lda #BAR_SOLID
        jmp box_on_barrier
; X = fighter -> carry set when it stands on a fuzzy barrier
fighter_fuzzy:
        jsr fighter_box
        lda #BAR_FUZZY
        jmp box_on_barrier

; X = fighter -> the box bx0..bx1 (units), by0..by1 (pixels)
fighter_box:
        lda f_x,x
        clc
        adc #2
        sta bx0
        adc #8
        sta bx1
        lda f_y,x
        clc
        adc #2
        sta by0
        adc #14
        sta by1
        rts
bx0:            .byte 0
bx1:            .byte 0
by0:            .byte 0
by1:            .byte 0

; A = barrier state -> carry set when box bx/by overlaps a barrier in that state
; (Y = its cell). Keeps X.
box_on_barrier:
        sta tmp3
        ldy #BAR_COLS * BAR_ROWS - 1
_cell:  lda bar_cell,y
        bmi _next
        jsr group_state
        cmp tmp3
        bne _next
        lda l_cell_ux,y                 ; cell: x .. x+7 units, y .. y+15
        cmp bx1
        beq +
        bcs _next
+       clc
        adc #7
        cmp bx0
        bcc _next
        lda l_cell_y,y
        cmp by1
        beq +
        bcs _next
+       clc
        adc #15
        cmp by0
        bcc _next
        sec
        rts
_next:  dey
        bpl _cell
        clc
        rts
; cell positions: screen column 5 + 4c (x = 40 + 32c px = 20 + 16c units), row 2 + 4r
l_cell_ux:
        .for r in range(BAR_ROWS)
        .byte 20 + range(BAR_COLS) * 16
        .next
l_cell_y:
        .for r in range(BAR_ROWS)
        .fill BAR_COLS, 16 + r * 32
        .next

;---------------------------------------------------------------------------------------
; X = fighter, fire held: launch an attack in the stick's direction if ready
try_attack:
        lda f_reload,x
        bne _out
        lda end_timer                   ; someone has died: no new attacks
        bne _out
        lda f_stick,x
        and #$0f
        sta tmp0                        ; aim
        lda f_kind,x
        cmp #ATK_AREA
        beq _area                       ; Phoenix, Banshee: no aim needed
        lda tmp0
        beq _out
        lda m_on,x                      ; a sword still swinging
        beq +
        lda f_kind,x
        cmp #ATK_MELEE
        beq _out
+       ldy f_type,x
        lda type_reload,y
        sta f_reload,x
        inc dbg_shots
        bne +
        inc dbg_shots+1
+       jsr aim_pose
        lda f_kind,x
        cmp #ATK_MELEE
        beq _melee
        ; a missile: speed along each aimed axis
        and #$1f
        sta tmp1
        lda #MISSILE_LIFE
        sta m_on,x
        jsr launch_offset
        lda #0
        sta m_dx,x
        sta m_dy,x
        lda tmp0
        and #JOY_RIGHT
        beq +
        lda tmp1
        sta m_dx,x
+       lda tmp0
        and #JOY_LEFT
        beq +
        lda #0
        sec
        sbc tmp1
        sta m_dx,x
+       lda tmp0
        and #JOY_DOWN
        beq +
        lda tmp1
        sta m_dy,x
+       lda tmp0
        and #JOY_UP
        beq +
        lda #0
        sec
        sbc tmp1
        sta m_dy,x
+       jmp sound_attack
_melee: lda #MELEE_FRAMES
        sta m_on,x
        lda #0
        sta m_dx,x
        sta m_dy,x
        sta m_hit,x
        jsr launch_offset
        lda #MELEE_FRAMES
        sta f_pose,x
        jmp sound_attack
_area:  lda m_on,x
        bne _out
        ldy f_type,x
        lda type_reload,y
        sta f_reload,x
        inc dbg_shots
        bne +
        inc dbg_shots+1
+       lda #PHOENIX_FRAMES
        cpy #TYPE_PHOENIX
        beq +
        lda #BANSHEE_FRAMES
+       sta m_on,x
        jmp sound_attack
_out:   rts
MISSILE_LIFE    = $ff                   ; flying missiles end on a hit, a wall or a barrier

; X = fighter, tmp0 = aim: the attack frame, and the missile image for that direction
aim_pose:
        ldy #7
-       lda l_aim_dirs,y
        cmp tmp0
        beq +
        dey
        bpl -
        ldy #2                          ; (an impossible stick: right)
+       lda l_aim_frame,y
        sta f_frame,x
        lda #POSE_FRAMES
        sta f_pose,x
        lda l_aim_missile,y
        clc
        adc l_set_id,x
        sta m_spr,x
        lda tmp0
        sta f_dir,x
        rts
l_aim_dirs:     .byte JOY_UP, JOY_UP | JOY_RIGHT, JOY_RIGHT, JOY_DOWN | JOY_RIGHT
                .byte JOY_DOWN, JOY_UP | JOY_LEFT, JOY_LEFT, JOY_DOWN | JOY_LEFT
l_aim_frame:    .byte 12, 13, 14, 15, 16, 21, 22, 23
l_aim_missile:  .byte FR_MISSILE + 1, FR_MISSILE + 2, FR_MISSILE + 0, FR_MISSILE + 3
                .byte FR_MISSILE + 1, FR_MISSILE + 5, FR_MISSILE + 4, FR_MISSILE + 6

; X = fighter, tmp0 = aim -> m_x / m_y where the attack starts ($9626-$9727)
launch_offset:
        lda f_x,x
        sta m_x,x
        lda f_y,x
        sta m_y,x
        lda tmp0
        and #JOY_RIGHT
        beq +
        lda #9
        bra _addx
+       lda tmp0
        and #JOY_LEFT
        beq +
        lda #256 - 7
        bra _addx
+       lda tmp0                        ; vertical only: +2 up, +1 down
        and #JOY_UP
        beq +
        lda #2
        bra _addx
+       lda #1
_addx:  clc
        adc m_x,x
        sta m_x,x
        lda tmp0
        and #JOY_UP | JOY_DOWN
        bne +
        lda #4                          ; horizontal: a little lower
        bra _addy
+       and #JOY_UP
        beq _down
        lda #256 - 7
        sta tmp2
        lda tmp0
        and #JOY_LEFT | JOY_RIGHT
        beq +
        lda #4                          ; diagonal up
        clc
        adc tmp2
        sta tmp2
+       lda tmp2
        bra _addy
_down:  lda #16
        sta tmp2
        lda tmp0
        and #JOY_LEFT | JOY_RIGHT
        beq +
        lda tmp2
        sec
        sbc #4
        sta tmp2
+       lda tmp2
_addy:  clc
        adc m_y,x
        sta m_y,x
        rts

;---------------------------------------------------------------------------------------
; X = fighter: move its attack and test it against the foe
attack_update:
        lda m_on,x
        bne +
        rts
+       lda f_kind,x
        cmp #ATK_AREA
        bne +
        jmp area_update
+       cmp #ATK_MELEE
        beq _melee
        ; a missile: half speed through a fuzzy barrier
        jsr missile_box
        lda #BAR_FUZZY
        jsr box_on_barrier
        bcc +
        lda cmb_frame
        lsr
        bcs _test
+       lda m_x,x
        clc
        adc m_dx,x
        sta m_x,x
        lda m_y,x
        clc
        adc m_dy,x
        sta m_y,x
        cmp #MY_MIN
        bcc _end
        cmp #MY_MAX
        bcs _end
        lda m_x,x
        cmp #MX_MIN
        bcc _end
        cmp #MX_MAX
        bcs _end
        jsr missile_box
        lda #BAR_SOLID
        jsr box_on_barrier
        bcs _end
_test:  jsr missile_box
        jsr hits_foe
        bcc _out
        jsr damage_foe
_end:   lda #0
        sta m_on,x
        jmp sound_attack_end
_out:   rts
_melee: dec m_on,x
        lda m_hit,x
        bne _out
        jsr missile_box
        jsr hits_foe
        bcc _out
        lda #1
        sta m_hit,x
        jmp damage_foe

; X = fighter -> box of its missile / sword (8 x 8 pixels at m_x, m_y)
missile_box:
        lda m_x,x
        sta bx0
        clc
        adc #3
        sta bx1
        lda m_y,x
        sta by0
        clc
        adc #7
        sta by1
        rts

; X = fighter: carry set when box bx/by overlaps the living foe's box
hits_foe:
        txa
        eor #1
        tay
        lda f_hp,y
        beq _no
        lda f_x,y
        clc
        adc #2
        cmp bx1
        beq +
        bcs _no
+       clc
        adc #8
        cmp bx0
        bcc _no
        lda f_y,y
        clc
        adc #2
        cmp by1
        beq +
        bcs _no
+       clc
        adc #14
        cmp by0
        bcc _no
        lda dbg_boxhits                 ; (test switch: boxes only)
        beq +
        sec
        rts
+       jmp pixel_hit                   ; the boxes touch: do the pixels?
_no:    clc
        rts
dbg_boxhits:    .byte 0                 ; tests: 1 = hits by box overlap only
dbg_shots:      .word 0                 ; tests: attacks launched / hits landed
dbg_hits:       .word 0

; X = attacker, Y = foe: carry set when an opaque pixel of X's missile (its image at
; m_x, m_y) lies on an opaque pixel of Y's frame - the original's sprite collision
pixel_hit:
        sty l_ph_foe
        lda m_spr,x                     ; the missile image as drawn
        phy
        ldy f_type,x
        jsr l_animated
        ply
        sta touch_a
        jsr l_foe_frame
        lda f_x,y                       ; B - A: dx = 2 * (f_x - m_x), dy = f_y - m_y
        sec
        sbc m_x,x
        asl
        sta touch_dx
        lda f_y,y
        sec
        sbc m_y,x
        sta touch_dy
        jsr sprite_touch
        ldy l_ph_foe
        rts
l_ph_foe:       .byte 0

; Y = foe -> touch_b = the sprite of its current frame
l_foe_frame:
        lda f_frame,y
        clc
        adc l_set_id,y
        sta touch_b
        rts

; X = attacker: the foe loses the attack force (a Phoenix in flames is unharmed)
damage_foe:
        txa
        eor #1
        tay
        lda f_type,y
        cmp #TYPE_PHOENIX
        bne +
        lda m_on,y
        bne _out
+       inc dbg_hits
        bne +
        inc dbg_hits+1
+       lda f_hp,y
        sec
        sbc f_force,x
        bcs +
        lda #0
+       sta f_hp,y
        lda #8
        sta f_hurt,y
        lda f_hp,y
        bne +
        lda #END_FRAMES                 ; a death: the arena closes soon
        sta end_timer
        jsr sound_death
        rts
+       jmp sound_hit
_out:   rts

; X = fighter with an area attack: the Phoenix's explosion or the Banshee's wail
area_update:
        lda f_hp,x
        bne +
        lda #0                          ; the wail stops when she dies
        sta m_on,x
        rts
+       dec m_on,x
        stx l_ar_attacker
        lda f_type,x
        cmp #TYPE_PHOENIX
        bne _wail
        ; five stages of 10 frames, a test on frame 5 of each
        lda #PHOENIX_FRAMES
        sec
        sbc m_on,x
        ldy #0
-       cmp #10
        bcc +
        sbc #10
        iny
        bra -
+       cmp #5
        bne _out
        cpy #2                          ; stage 2 is the doubled fire (4 tiles)
        beq _big
        lda #SPR_FIRE0                  ; stages 0, 4: frame 0; 1, 3: frame 1
        cpy #1
        beq +
        cpy #3
        bne ++
+       lda #SPR_FIRE1
+       sta touch_a
        lda #0
        sta l_ar_off
        lda #1
        bra _test
_big:   lda #SPR_FIREBIG0
        bra _tiles
_wail:  lda m_on,x                      ; a test every 5 frames
-       cmp #5
        bcc +
        sbc #5
        bra -
+       cmp #0
        bne _out
        lda cmb_frame                   ; the ring being shown
        lsr
        lsr
        and #3
        asl
        asl
        clc
        adc #SPR_WAIL0_0
_tiles: sta touch_a
        lda #12                         ; doubled pictures sit 12 px up and left
        sta l_ar_off
        lda #4
_test:  sta l_ar_n                      ; tiles to test
        txa
        eor #1
        tay
        lda f_hp,y
        beq _out
        lda f_x,y                       ; far apart: no need to look
        sec
        sbc f_x,x
        bcs +
        eor #$ff
        inc a
+       cmp #28
        bcs _out
        jsr l_foe_frame
        lda #0
        sta l_ar_i
_tile:  ; B (the foe) - A (this tile): 2 * (foe x - x) + off - tile column, and for y
        ldx l_ar_attacker
        lda f_x,y
        sec
        sbc f_x,x
        asl
        clc
        adc l_ar_off
        ldx l_ar_i
        sec
        sbc l_tile_dx,x
        sta touch_dx
        ldx l_ar_attacker
        lda f_y,y
        sec
        sbc f_y,x
        clc
        adc l_ar_off
        ldx l_ar_i
        sec
        sbc l_tile_dy,x
        sta touch_dy
        ldx l_ar_attacker
        jsr sprite_touch
        bcs _hit
        inc touch_a
        inc l_ar_i
        lda l_ar_i
        cmp l_ar_n
        bne _tile
_out:   rts
_hit:   jmp damage_foe
l_ar_off:       .byte 0
l_ar_n:         .byte 0
l_ar_i:         .byte 0
l_ar_attacker:  .byte 0
l_tile_dx:      .byte 0, SPR_W, 0, SPR_W
l_tile_dy:      .byte 0, 0, SPR_H, SPR_H

;=======================================================================================
; drawing
;=======================================================================================
ARENA_X0        = 8                     ; the field inside the walls (pixels)
ARENA_Y0        = 16
ARENA_X1        = 312
ARENA_Y1        = 192

arena_draw:
        lda bar_version                 ; walls and barriers: cached until they change
        ora #$80
        jsr cache_restore
        bcc +
        lda #COL_BG
        jsr fcm_clear
        jsr l_ad_walls
        jsr l_ad_barriers
        jsr cache_save
+       ldx #1
-       phx
        jsr l_ad_fighter
        plx
        phx
        jsr l_ad_attack
        plx
        dex
        bpl -
        jmp l_ad_lifelines

; walls in the disputed square's colour, with the fighters' names
l_ad_walls:
        ldx combat_l
        lda l_wall_col,x
        sta l_aw_col
        lda #0
        sta box_x
        sta box_x+1
        sta box_y
        lda #160                        ; (box takes a byte width: two halves)
        sta box_w
        lda #ARENA_Y0
        sta box_h
        lda l_aw_col
        jsr box
        lda #160
        sta box_x
        lda l_aw_col
        jsr box
        lda #ARENA_Y1
        sta box_y
        lda #200 - ARENA_Y1
        sta box_h
        lda l_aw_col
        jsr box
        lda #0
        sta box_x
        lda l_aw_col
        jsr box
        lda #ARENA_Y0
        sta box_y
        lda #ARENA_X0
        sta box_w
        lda #ARENA_Y1 - ARENA_Y0
        sta box_h
        lda l_aw_col
        jsr box
        lda #<ARENA_X1
        sta box_x
        lda #>ARENA_X1
        sta box_x+1
        lda l_aw_col
        jsr box
        ; a dark inner edge
        lda l_aw_col
        clc
        adc #3
        sta draw_col
        lda #<(ARENA_X0 - 1)
        sta draw_x0
        lda #0
        sta draw_x0+1
        lda #ARENA_Y0 - 1
        sta draw_y0
        lda #<(ARENA_X1 - ARENA_X0 + 2)
        sta draw_w
        lda #>(ARENA_X1 - ARENA_X0 + 2)
        sta draw_w+1
        lda #ARENA_Y1 - ARENA_Y0 + 2
        sta draw_h
        jsr draw_rect
        ; names: Light at the left, Dark at the right
        lda #4
        sta ftext_y
        lda #COL_SHADOW                 ; light text, or dark on the bright walls
        sta ftext_shadow
        lda #COL_TEXT
        sta ftext_col
        lda combat_l
        cmp #5
        bcc +
        lda #COL_SHADOW
        sta ftext_col
        lda #0
        sta ftext_shadow
+
        lda #16
        sta ftext_x
        lda #0
        sta ftext_x+1
        ldy combat_slot                 ; (names by slot: a Shapeshifter stays one)
        ldx slot_type,y
        jsr l_ad_name
        ldy combat_slot+1               ; right-aligned: x = 304 - len * 8
        ldx slot_type,y
        jsr l_type_name
        sta str_ptr
        stx str_ptr+1
        ldy #0
-       lda (str_ptr),y
        beq +
        iny
        bra -
+       tya
        asl
        asl
        asl
        sta tmp0
        sec
        lda #<304
        sbc tmp0
        sta ftext_x
        lda #>304
        sbc #0
        sta ftext_x+1
        lda str_ptr
        ldx str_ptr+1
        jmp ftext_draw
l_ad_name:
        jsr l_type_name
        jmp ftext_draw
; X = type -> A/X = its name (the "NAME (MOVE n)" message up to the space)
l_type_name:
        lda l_name_lo_t,x
        pha
        lda l_name_hi_t,x
        tax
        pla
        rts
l_aw_col:       .byte 0
; walls: L 0 is drawn dark grey as in the original; the others use the luminance colours
l_wall_col:     .byte COL_DIM, COL_LUM1, COL_RED, COL_LUM2, COL_LUM3, COL_GOLD, COL_LUM4, COL_LUM5
l_name_lo_t:    .byte <tn0, <tn1, <tn2, <tn3, <tn4, <tn5, <tn6, <tn7, <tn8, <tn9
                .byte <tn10, <tn11, <tn12, <tn13, <tn14, <tn15, <tn16, <tn17, <tn18, <tn19
l_name_hi_t:    .byte >tn0, >tn1, >tn2, >tn3, >tn4, >tn5, >tn6, >tn7, >tn8, >tn9
                .byte >tn10, >tn11, >tn12, >tn13, >tn14, >tn15, >tn16, >tn17, >tn18, >tn19
tn0:    .null "UNICORN"
tn1:    .null "WIZARD"
tn2:    .null "ARCHER"
tn3:    .null "GOLEM"
tn4:    .null "VALKYRIE"
tn5:    .null "DJINNI"
tn6:    .null "PHOENIX"
tn7:    .null "KNIGHT"
tn8:    .null "BASILISK"
tn9:    .null "SORCERESS"
tn10:   .null "MANTICORE"
tn11:   .null "TROLL"
tn12:   .null "SHAPESHIFTER"
tn13:   .null "DRAGON"
tn14:   .null "BANSHEE"
tn15:   .null "GOBLIN"
tn16:   .null "AIR ELEMENTAL"
tn17:   .null "FIRE ELEMENTAL"
tn18:   .null "EARTH ELEMENTAL"
tn19:   .null "WATER ELEMENTAL"

l_ad_barriers:
        ldy #BAR_COLS * BAR_ROWS - 1
_cell:  lda bar_cell,y
        bmi _next
        sta tmp0
        tax
        lda grp_lum,x
        beq _next                       ; black: gone
        ; sprite = SPR_BARRIER + (group * 7 + L - 1) * 2 + faded
        sta tmp1
        lda tmp0
        asl
        asl
        asl
        sec
        sbc tmp0                        ; group * 7
        clc
        adc tmp1
        dec a
        asl
        sta tmp2
        lda tmp1
        cmp #2
        bcs +
        inc tmp2                        ; blue = fuzzy: the faded look
+       lda tmp2
        clc
        adc #SPR_BARRIER
        sta bs_id
        lda l_cell_ux,y
        asl
        sta bs_x
        lda #0
        rol
        sta bs_x+1
        lda l_cell_y,y                  ; a pillar stands on its box, rising above it
        sec
        sbc #BAR_RISE
        sta bs_y
        lda #0
        sta bs_y+1
        phy
        jsr blit_sprite
        ply
_next:  dey
        bpl _cell
        rts

; X = fighter: its frame at (2x, y); a Phoenix in flames is only fire; a hit flickers
l_ad_fighter:
        lda f_hp,x
        beq _out
        lda f_type,x
        cmp #TYPE_PHOENIX
        bne +
        lda m_on,x
        bne _out
+       lda f_hurt,x
        and #2
        bne _out
        lda f_frame,x
        clc
        adc l_set_id,x
        sta bs_id
        jsr l_ad_pos
        jmp blit_sprite
_out:   rts

; bs_x / bs_y = fighter X's screen position
l_ad_pos:
        lda f_x,x
        asl
        sta bs_x
        lda #0
        rol
        sta bs_x+1
        lda f_y,x
        sta bs_y
        lda #0
        sta bs_y+1
        rts

; X = fighter: its missile, sword, flames or wail
l_ad_attack:
        lda m_on,x
        bne +
        rts
+       lda f_kind,x
        cmp #ATK_AREA
        beq _area
        lda m_spr,x                     ; animated missiles cycle their 4 images
        ldy f_type,x
        jsr l_animated
        sta bs_id
        lda m_x,x
        asl
        sta bs_x
        lda #0
        rol
        sta bs_x+1
        lda m_y,x
        sta bs_y
        lda #0
        sta bs_y+1
        jmp blit_sprite
_area:  jsr l_ad_pos
        lda f_type,x
        cmp #TYPE_PHOENIX
        bne _wail
        lda #PHOENIX_FRAMES             ; stage 0-4: small, frame 1, big, frame 1, small
        sec
        sbc m_on,x
        ldy #0
-       cmp #10
        bcc +
        sbc #10
        iny
        bra -
+       cpy #2
        beq _big
        lda #SPR_FIRE0
        cpy #1
        beq +
        cpy #3
        bne ++
+       lda #SPR_FIRE1
+       sta bs_id
        jmp blit_sprite
_big:   lda #SPR_FIREBIG0               ; doubled, 12 px up and left
        ldy #12
        jmp l_ad_quad
_wail:  lda cmb_frame                   ; four rings, cycling, doubled
        lsr
        lsr
        and #3
        asl
        asl
        clc
        adc #SPR_WAIL0_0
        ldy #12
; A = first of 4 tiles (48 x 42), drawn Y pixels up and left of bs_x / bs_y
l_ad_quad:
        sta l_aq_id
        sty tmp0
        sec
        lda bs_x
        sbc tmp0
        sta bs_x
        lda bs_x+1
        sbc #0
        sta bs_x+1
        sec
        lda bs_y
        sbc tmp0
        sta bs_y
        lda bs_y+1
        sbc #0
        sta bs_y+1
        lda #0
        sta l_aq_i
-       lda l_aq_id
        clc
        adc l_aq_i
        sta bs_id
        jsr blit_sprite
        lda l_aq_i
        inc a
        sta l_aq_i
        cmp #4
        beq +
        cmp #2                          ; next tile: right, or down and back left
        beq _row
        clc
        lda bs_x
        adc #SPR_W
        sta bs_x
        bcc -
        inc bs_x+1
        bra -
_row:   sec
        lda bs_x
        sbc #SPR_W
        sta bs_x
        bcs ++
        dec bs_x+1
+       rts
+       clc
        lda bs_y
        adc #SPR_H
        sta bs_y
        bcc -
        inc bs_y+1
        bra -
l_aq_id:        .byte 0
l_aq_i:         .byte 0

; A = missile sprite, Y = type: animated missiles (boulders, fireballs, whirlwinds)
; show images 0-3 of the set in turn instead of a direction
l_animated:
        cpy #1
        beq _anim
        cpy #3
        beq _anim
        cpy #5
        beq _anim
        cpy #11
        beq _anim
        cpy #16
        bcs _anim
        rts
_anim:  lda cmb_frame
        lsr
        lsr
        and #3
        clc
        adc #FR_MISSILE
        adc l_set_id,x
        rts

; the lifelines: Light at the left edge, Dark at the right, 8 pixels per point
l_ad_lifelines:
        ldx #1
-       lda f_hp,x
        beq _next
        asl
        asl
        asl
        sta box_h
        lda #ARENA_Y1
        sec
        sbc box_h
        sta box_y
        lda l_life_x,x
        sta box_x
        lda l_life_x_hi,x
        sta box_x+1
        lda #6
        sta box_w
        phx
        lda l_side_col,x
        jsr box
        plx
_next:  dex
        bpl -
        rts
l_life_x:       .byte 1, <(ARENA_X1 + 1)
l_life_x_hi:    .byte 0, >(ARENA_X1 + 1)
