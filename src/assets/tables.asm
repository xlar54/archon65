; tables.asm - icon stats, board, messages;
; edit freely (a new import overwrites it).

; per icon type 0-19 (0-7 light, 8-15 dark, 16-19 elementals)
NTYPES = 20
NSLOTS = 40
type_life:
        .byte $09,$0a,$05,$0f,$08,$0f,$0c,$05,$06,$0a,$08,$0e,$0a,$11,$08,$05,$0c,$0a,$11,$0e
type_force:
        .byte $07,$0a,$05,$0a,$07,$06,$02,$05,$09,$08,$04,$0a,$00,$0b,$01,$05,$05,$09,$09,$06
type_reload:
        .byte $3c,$50,$50,$64,$50,$5a,$64,$28,$3c,$50,$50,$64,$00,$78,$64,$28,$46,$3c,$64,$64
; bit 7 fly, bit 6 teleport, bits 0-5 range
type_move:
        .byte $04,$c3,$03,$03,$83,$84,$85,$03,$03,$c3,$03,$03,$85,$84,$83,$03,$8f,$8f,$8f,$8f
; bit 5 melee, bit 6 area attack, bit 7 copies the foe, else missile speed
type_attack:
        .byte $07,$05,$04,$03,$03,$05,$40,$20,$07,$06,$03,$03,$80,$04,$40,$20,$04,$05,$03,$03
type_slow:
        .byte $00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$01,$00
; icon slot -> type: 0-17 light, 18-35 dark, 36-39 elementals
slot_type:
        .byte $04,$02,$03,$07,$00,$07,$05,$07,$01,$07,$06,$07,$00,$07,$03,$07,$04,$02,$0a,$0e
        .byte $0f,$0b,$0f,$08,$0f,$0c,$0f,$09,$0f,$0d,$0f,$08,$0f,$0b,$0a,$0e,$10,$11,$12,$13
; the starting board, row-major: slot or $80 = empty
board_start:
        .byte $00,$01,$80,$80,$80,$80,$80,$12,$13
        .byte $02,$03,$80,$80,$80,$80,$80,$14,$15
        .byte $04,$05,$80,$80,$80,$80,$80,$16,$17
        .byte $06,$07,$80,$80,$80,$80,$80,$18,$19
        .byte $08,$09,$80,$80,$80,$80,$80,$1a,$1b
        .byte $0a,$0b,$80,$80,$80,$80,$80,$1c,$1d
        .byte $0c,$0d,$80,$80,$80,$80,$80,$1e,$1f
        .byte $0e,$0f,$80,$80,$80,$80,$80,$20,$21
        .byte $10,$11,$80,$80,$80,$80,$80,$22,$23
; square kinds: 0 always dark, 1 always light, 2 luminance
square_kind:
        .byte $00,$01,$00,$02,$02,$02,$01,$00,$01
        .byte $01,$00,$02,$01,$02,$00,$02,$01,$00
        .byte $00,$02,$01,$00,$02,$01,$00,$02,$01
        .byte $02,$01,$00,$01,$02,$00,$01,$00,$02
        .byte $01,$02,$02,$02,$02,$02,$02,$02,$00
        .byte $02,$01,$00,$01,$02,$00,$01,$00,$02
        .byte $00,$02,$01,$00,$02,$01,$00,$02,$01
        .byte $01,$00,$02,$01,$02,$00,$02,$01,$00
        .byte $00,$01,$00,$02,$02,$02,$01,$00,$01
pp_square:
        .byte $04,$24,$28,$2c,$4c
sq_up:
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $00,$01,$02,$03,$04,$05,$06,$07,$08
        .byte $09,$0a,$0b,$0c,$0d,$0e,$0f,$10,$11
        .byte $12,$13,$14,$15,$16,$17,$18,$19,$1a
        .byte $1b,$1c,$1d,$1e,$1f,$20,$21,$22,$23
        .byte $24,$25,$26,$27,$28,$29,$2a,$2b,$2c
        .byte $2d,$2e,$2f,$30,$31,$32,$33,$34,$35
        .byte $36,$37,$38,$39,$3a,$3b,$3c,$3d,$3e
        .byte $3f,$40,$41,$42,$43,$44,$45,$46,$47
sq_down:
        .byte $09,$0a,$0b,$0c,$0d,$0e,$0f,$10,$11
        .byte $12,$13,$14,$15,$16,$17,$18,$19,$1a
        .byte $1b,$1c,$1d,$1e,$1f,$20,$21,$22,$23
        .byte $24,$25,$26,$27,$28,$29,$2a,$2b,$2c
        .byte $2d,$2e,$2f,$30,$31,$32,$33,$34,$35
        .byte $36,$37,$38,$39,$3a,$3b,$3c,$3d,$3e
        .byte $3f,$40,$41,$42,$43,$44,$45,$46,$47
        .byte $48,$49,$4a,$4b,$4c,$4d,$4e,$4f,$50
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
sq_left:
        .byte $ff,$00,$01,$02,$03,$04,$05,$06,$07
        .byte $ff,$09,$0a,$0b,$0c,$0d,$0e,$0f,$10
        .byte $ff,$12,$13,$14,$15,$16,$17,$18,$19
        .byte $ff,$1b,$1c,$1d,$1e,$1f,$20,$21,$22
        .byte $ff,$24,$25,$26,$27,$28,$29,$2a,$2b
        .byte $ff,$2d,$2e,$2f,$30,$31,$32,$33,$34
        .byte $ff,$36,$37,$38,$39,$3a,$3b,$3c,$3d
        .byte $ff,$3f,$40,$41,$42,$43,$44,$45,$46
        .byte $ff,$48,$49,$4a,$4b,$4c,$4d,$4e,$4f
sq_right:
        .byte $01,$02,$03,$04,$05,$06,$07,$08,$ff
        .byte $0a,$0b,$0c,$0d,$0e,$0f,$10,$11,$ff
        .byte $13,$14,$15,$16,$17,$18,$19,$1a,$ff
        .byte $1c,$1d,$1e,$1f,$20,$21,$22,$23,$ff
        .byte $25,$26,$27,$28,$29,$2a,$2b,$2c,$ff
        .byte $2e,$2f,$30,$31,$32,$33,$34,$35,$ff
        .byte $37,$38,$39,$3a,$3b,$3c,$3d,$3e,$ff
        .byte $40,$41,$42,$43,$44,$45,$46,$47,$ff
        .byte $49,$4a,$4b,$4c,$4d,$4e,$4f,$50,$ff
; AI: positional value of each square ($721F)
ai_pos_value:
        .byte $28,$28,$28,$29,$2d,$29,$28,$28,$28
        .byte $27,$28,$28,$29,$2a,$29,$28,$28,$27
        .byte $28,$28,$28,$29,$2a,$29,$28,$28,$28
        .byte $28,$28,$29,$29,$2a,$29,$29,$28,$28
        .byte $2e,$28,$28,$29,$2d,$29,$28,$28,$2e
        .byte $28,$28,$29,$29,$2a,$29,$29,$28,$28
        .byte $28,$28,$28,$29,$2a,$29,$28,$28,$28
        .byte $27,$28,$28,$29,$2a,$29,$28,$28,$27
        .byte $28,$28,$28,$29,$2d,$29,$28,$28,$28
; AI combat, per type: aiming range, keep-away from this foe, foe lane width
ai_range:
        .byte $8a,$74,$54,$4e,$42,$74,$0f,$0c,$8f,$7e,$46,$4e,$00,$5c,$0f,$0c,$5f,$6f,$4e,$47
ai_keepaway:
        .byte $4e,$42,$2c,$30,$24,$42,$14,$0f,$49,$42,$28,$30,$00,$34,$14,$0f,$2c,$37,$30,$21
ai_lane:
        .byte $06,$08,$06,$09,$06,$08,$15,$06,$07,$06,$08,$09,$00,$07,$15,$06,$08,$08,$09,$08
NMESSAGES = 71
msg_lo: .byte <msg_00,<msg_01,<msg_02,<msg_03,<msg_04,<msg_05,<msg_06,<msg_07,<msg_08,<msg_09,<msg_0a,<msg_0b,<msg_0c,<msg_0d,<msg_0e,<msg_0f,<msg_10,<msg_11,<msg_12,<msg_13,<msg_14,<msg_15,<msg_16,<msg_17,<msg_18,<msg_19,<msg_1a,<msg_1b,<msg_1c,<msg_1d,<msg_1e,<msg_1f,<msg_20,<msg_21,<msg_22,<msg_23,<msg_24,<msg_25,<msg_26,<msg_27,<msg_28,<msg_29,<msg_2a,<msg_2b,<msg_2c,<msg_2d,<msg_2e,<msg_2f,<msg_30,<msg_31,<msg_32,<msg_33,<msg_34,<msg_35,<msg_36,<msg_37,<msg_38,<msg_39,<msg_3a,<msg_3b,<msg_3c,<msg_3d,<msg_3e,<msg_3f,<msg_40,<msg_41,<msg_42,<msg_43,<msg_44,<msg_45,<msg_46
msg_hi: .byte >msg_00,>msg_01,>msg_02,>msg_03,>msg_04,>msg_05,>msg_06,>msg_07,>msg_08,>msg_09,>msg_0a,>msg_0b,>msg_0c,>msg_0d,>msg_0e,>msg_0f,>msg_10,>msg_11,>msg_12,>msg_13,>msg_14,>msg_15,>msg_16,>msg_17,>msg_18,>msg_19,>msg_1a,>msg_1b,>msg_1c,>msg_1d,>msg_1e,>msg_1f,>msg_20,>msg_21,>msg_22,>msg_23,>msg_24,>msg_25,>msg_26,>msg_27,>msg_28,>msg_29,>msg_2a,>msg_2b,>msg_2c,>msg_2d,>msg_2e,>msg_2f,>msg_30,>msg_31,>msg_32,>msg_33,>msg_34,>msg_35,>msg_36,>msg_37,>msg_38,>msg_39,>msg_3a,>msg_3b,>msg_3c,>msg_3d,>msg_3e,>msg_3f,>msg_40,>msg_41,>msg_42,>msg_43,>msg_44,>msg_45,>msg_46
msg_00: .text "OH, WOE! YOUR SPELLS ARE GONE!", 0
msg_01: .text "ALAS, MASTER, THIS ICON CANNOT MOVE", 0
msg_02: .text "DO YOU CHALLENGE THIS FOE?", 0
msg_03: .text "YOU HAVE MOVED YOUR LIMIT", 0
msg_04: .text "THE SQUARE AHEAD IS OCCUPIED", 0
msg_05: .text "IT IS DONE", 0
msg_06: .text "THE LIGHT SIDE WINS", 0
msg_07: .text "THE DARK SIDE WINS", 0
msg_08: .text "IT IS A TIE", 0
msg_09: .text "THE FLOW OF TIME IS REVERSED", 0
msg_0a: .text "WHICH ICON WILL YOU HEAL?", 0
msg_0b: .text "WHICH ICON WILL YOU TELEPORT?", 0
msg_0c: .text "WHERE WILL YOU TELEPORT IT?", 0
msg_0d: .text "CHOOSE AN ICON TO TRANSPOSE", 0
msg_0e: .text "EXCHANGE IT WITH WHICH ICON?", 0
msg_0f: .text "WHAT ICON WILL YOU REVIVE?", 0
msg_10: .text "PLACE IT WITHIN THE CHARMED SQUARE", 0
msg_11: .text "WHICH FOE WILL YOU IMPRISON?", 0
msg_12: .text "ALAS, MASTER, THERE IS NO OPENING IN THE", 13, "CHARMED SQUARE. CONJURE ANOTHER SPELL", 0
msg_13: .text "HAPPILY, MASTER, ALL YOUR ICONS LIVE.", 13, "PLEASE CONJURE A DIFFERENT SPELL", 0
msg_14: .text "ALAS, THIS ICON IS IMPRISONED", 0
msg_15: .text "AN AIR", 0
msg_16: .text "A FIRE", 0
msg_17: .text "AN EARTH", 0
msg_18: .text "A WATER", 0
msg_19: .text "SEND IT TO THE TARGET", 0
msg_1a: .text "THE WIZARD", 0
msg_1b: .text "THE SORCERESS", 0
msg_1c: .text "UNICORN (GROUND 4)", 0
msg_1d: .text "WIZARD (TELEPORT 3)", 0
msg_1e: .text "ARCHER (GROUND 3)", 0
msg_1f: .text "GOLEM (GROUND 3)", 0
msg_20: .text "VALKYRIE (FLY 3)", 0
msg_21: .text "DJINNI (FLY 4)", 0
msg_22: .text "PHOENIX (FLY 5)", 0
msg_23: .text "KNIGHT (GROUND 3)", 0
msg_24: .text "BASILISK (GROUND 3)", 0
msg_25: .text "SORCERESS (TELEPORT 3)", 0
msg_26: .text "MANTICORE (GROUND 3)", 0
msg_27: .text "TROLL (GROUND 3)", 0
msg_28: .text "SHAPESHIFTER (FLY 5)", 0
msg_29: .text "DRAGON (FLY 4)", 0
msg_2a: .text "BANSHEE (FLY 3)", 0
msg_2b: .text "GOBLIN (GROUND 3)", 0
msg_2c: .text "TELEPORT", 0
msg_2d: .text "HEAL", 0
msg_2e: .text "SHIFT TIME", 0
msg_2f: .text "EXCHANGE", 0
msg_30: .text "SUMMON ELEMENTAL", 0
msg_31: .text "REVIVE", 0
msg_32: .text "IMPRISON", 0
msg_33: .text "CEASE CONJURING", 0
msg_34: .text "POWER POINTS ARE PROOF AGAINST MAGIC", 0
msg_35: .text "THAT SPELL WOULD BE WASTED AT THIS TIME", 0
msg_36: .text "SELECT A SPELL", 0
msg_37: .text "COMPUTER", 0
msg_38: .text "LIGHT", 0
msg_39: .text "TWO-PLAYER", 0
msg_3a: .text "FIRST", 0
msg_3b: .text "DARK", 0
msg_3c: .text "WHEN READY", 0
msg_3d: .text " PRESS", 0
msg_3e: .text "SPELL IS CANCELED. CHOOSE ANOTHER", 0
msg_3f: .text "THE GAME IS ENDED...", 0
msg_40: .text "IT IS A STALEMATE", 0
msg_41: .text " ELEMENTAL APPEARS!", 0
msg_42: .text " CONJURES A SPELL!", 0
msg_43: .text "PRESS RUN KEY TO CONTINUE", 0
msg_44: .text "F7", 0
msg_45: .text "F5:", 0
msg_46: .text "F3:", 0
