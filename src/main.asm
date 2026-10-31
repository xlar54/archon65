;=======================================================================================
; Archon65 - a MEGA65 remake of Archon (Free Fall Associates, 1983).
;
; Boot: load the assets into attic RAM with the KERNAL, then take over the machine.
; Game code is written as plain sequential logic that calls `frame` whenever it waits:
; frame draws the current scene into the back buffer, shows it, and reads the input.
;
;   main.asm     boot, frame, the top level (title -> game -> result)
;   gfx.asm      palette, text          board.asm   drawing the strategy screen
;   game.asm     rules, turn loop       player.asm  controls, the human's moves
;   spells.asm   the seven spells       combat.asm  the arena
;   ai.asm       the computer player    sound.asm   SID effects and music
;   title.asm    title and options      fx.asm      spell effects (hardware sprites)
;=======================================================================================
        .cpu "45gs02"

        .include "platform.asm"
        .include "lib/zp.asm"
        .include "zp.asm"
        .include "gen/colours.asm"

SCENE_TITLE     = 0
SCENE_BOARD     = 1
SCENE_ARENA     = 2

        * = $2001                       ; BASIC stub: BANK 0 : SYS 8210
        .word (+), 2026
        .byte $fe, $02, $30
        .byte ':'
        .byte $9e
        .text "8210"
        .byte 0
+       .word 0

        * = $2012
entry:
        cld
        jsr boot_load
        #TAKEOVER
        jsr irq_install
        jsr rom_unprotect
        jsr load_sprites
        cli
        jsr gfx_init
        jsr fx_init
        jsr sound_init
        jsr rand_seed_hw

main_loop:
        jsr title_run
        lda #SCENE_BOARD
        sta scene
        jsr game_play
        lda game_result
        cmp #RESULT_QUIT
        beq main_loop
        jsr game_over
        bra main_loop

;---------------------------------------------------------------------------------------
; frame - draw the scene, show it at the next vertical blank, read the controls.
; RUN/STOP pauses (in the arena against the computer), Q abandons the game, and in the
; demo any key or joystick press does.
scene:          .byte SCENE_TITLE
paused:         .byte 0
frame_key:      .byte 0                 ; key typed this frame (lib/keyboard.asm codes)
frames_shown:   .byte 0                 ; +1 per frame drawn (frame rate = this / frame_count)

frame:
        lda scene
        asl
        tax
        jsr (l_scene_draw,x)
        jsr fcm_present
        jsr fx_update
        inc frames_shown
        jsr read_input
        jsr ctl_update
        jsr key_get
        sta frame_key
        lda demo                        ; the demo: any key or joystick press ends it
        beq +
        lda frame_key
        ora joy_new
        bne _quit
+       lda frame_key
        cmp #'q'
        beq _quit
        cmp #'Q'
        beq _quit
        cmp #K_STOP
        bne +
        lda paused
        eor #1
        sta paused
+       rts
_quit:  lda scene
        cmp #SCENE_TITLE
        beq +
        lda #RESULT_QUIT
        sta game_result
+       rts
l_scene_draw:   .word title_draw, board_draw, arena_draw

;---------------------------------------------------------------------------------------
; the sprite sheet: attic -> chip RAM at SPR_BASE, and its bounding boxes
load_sprites:
        lda #<ATTIC_SPRITES
        sta ptr1
        lda #>ATTIC_SPRITES
        sta ptr1+1
        lda #`ATTIC_SPRITES
        sta ptr1+2
        lda #ATTIC_SPRITES >> 24
        sta ptr1+3
        lda #<SPR_BASE
        sta ptr2
        lda #>SPR_BASE
        sta ptr2+1
        lda #`SPR_BASE
        sta ptr2+2
        lda #0
        sta ptr2+3
        lda #<SPRITES_BYTES
        sta tmp5
        lda #>SPRITES_BYTES
        sta tmp5+1
        jsr dma_copy_far
        ldx #0
-       lda #1                          ; unused ids: empty boxes
        sta spr_x0,x
        lda #0
        sta spr_x1,x
        inx
        bne -
        ldx #SPR_COUNT - 1
-       lda sprite_x0,x
        sta spr_x0,x
        lda sprite_x1,x
        sta spr_x1,x
        lda sprite_y0,x
        sta spr_y0,x
        lda sprite_y1,x
        sta spr_y1,x
        dex
        bpl -
        rts

; wait A frames with the current scene on show
wait_frames:
        sta l_wf_n
-       jsr frame
        dec l_wf_n
        bne -
        rts
l_wf_n:         .byte 0

        .include "boot.asm"
        .include "gfx.asm"
        .include "board.asm"
        .include "game.asm"
        .include "player.asm"
        .include "spells.asm"
        .include "combat.asm"
        .include "ai.asm"
        .include "title.asm"
        .include "sound.asm"
        .include "fx.asm"

        .include "lib/system.asm"
        .include "lib/dma.asm"
        .include "lib/loader.asm"
        .include "lib/unpack.asm"
        .include "lib/input.asm"
        .include "lib/keyboard.asm"
        .include "lib/video_fcm.asm"
        .include "lib/blit.asm"
        .include "lib/sprite_touch.asm"
        .include "lib/draw.asm"
        .include "lib/hwsprite.asm"
        .include "lib/palette.asm"
        .include "lib/fcm_text.asm"
        .include "lib/fcm_cache.asm"
        .include "lib/math.asm"
        .include "assets/font.asm"
        .include "gen/palette.asm"
        .include "assets/tables.asm"
        .include "gen/manifest.asm"
        .include "assets/sound.asm"
        .include "gen/sprites.asm"
        .include "gen/effects.asm"

        .cerror * > $c7ff, "program overflows into screen RAM C at $C800"
