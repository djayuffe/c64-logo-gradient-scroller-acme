
; deepseek_asm_20251009_v9_logo_grad_scroller_embedded_fonts_vicfix_acme.s
; PAL-safe, single-IRQ rasterbars + tiny SID arpeggio.
; Uses your embedded custom 1bpp hires charset at $2000 and prints:
;   "UBER CREW" (row 8) and "2025" (row 10) centered in white.
;
; Build:
;   acme --strict-segments -f cbm -o v9_logo_grad.prg deepseek_asm_20251009_v9_logo_grad_scroller_embedded_fonts_vicfix_acme.s
; Run:
;   x64sc -autostart v9_logo_grad.prg

; ---------------- BASIC stub: 10 SYS4608 ----------------
* = $0801
!word $080b
!word 10
!byte $9e
!text "4608"
!byte 0
!word 0

; ---------------- Constants ----------------
BORDERCOL   = $d020
BGCOL       = $d021
RASTER      = $d012
CTRL1       = $d011
CTRL2       = $d016
MEMPTR      = $d018
VICIRQEN    = $d01a
VICIRQFLAG  = $d019
CIA2_PRA    = $dd00
CIA1_ICR    = $dc0d
CIA2_ICR    = $dd0d

SCREEN      = $0400
COLOR       = $d800
CHARSET     = $2000

; ---------------- Zero Page ----------------
ZP_SrcLo    = $fb   ; general pointer/param
ZP_SrcHi    = $fc
ZP_DstLo    = $fd
ZP_DstHi    = $fe
ZP_Tmp      = $ff   ; scratch / color

; ---------------- Small variables ----------------
Len         = $0340
FrameCount  = $0341
ArpIdx      = $0342
ScrIdx      = $0343
Smooth      = $0344
RowTmp      = $0345

; ---------------- Tables ----------------
* = $0900
RowScrLo:  !for i,0,24 { !byte <(SCREEN + i*40) }
RowScrHi:  !for i,0,24 { !byte >(SCREEN + i*40) }
RowColLo:  !for i,0,24 { !byte <(COLOR  + i*40) }
RowColHi:  !for i,0,24 { !byte >(COLOR  + i*40) }

; Badline-safe raster hits (y % 8 == 2 with $1B Y-scroll=3)
RasterLines: !byte 50,58,66,74,82,90,98,106,114,122,130,138,146,154,162,170
BarColors:   !byte 2,6,3,1,3,6,2,0,2,6,3,1,3,6,2,0

; Gradient for logo rows (white->light grey->grey->blue-ish via safe C64 colors)
LogoGrad16: !byte 1,15,14,6,14,15,1,1,15,14,6,14,15,1,1,1

; Scroller text (PETSCII mapped to our custom font)
ScrollTxt:
!scr "  UBER CREW 2025  -  GREETINGS TO: NTEB, DOMUS, JSWIKI, ULF, MAGNUS, THOMAS, ALEKS  -  "
!scr "  MADE WITH LOVE ON REAL C64  "
!byte 0


; ---------------- Code ----------------
* = $1200
Start:
    sei
    ; Disable CIA sources before installing the raster-only handler.
    lda #$7f
    sta CIA1_ICR
    sta CIA2_ICR
    lda CIA1_ICR
    lda CIA2_ICR
    jsr VIC_BankFix   ; ensure $dd00/$d018 are correct early
    ; VIC bank 0 ($0000-$3FFF)
    lda CIA2_PRA
    and #%11111100
    ora #%00000011
    sta CIA2_PRA

    ; Screen=$0400, Charset=$2000
    lda #$18
    sta MEMPTR

    ; Standard display
    lda #$1b
    sta CTRL1
    lda #$08
    sta CTRL2

    lda #0
    sta FrameCount
    sta ArpIdx

    jsr ClearScreen
    jsr ClearColor

    ; Draw centered text using custom font
    lda #8                      ; row
    lda #<Uber1
    sta ZP_SrcLo
    lda #>Uber1
    sta ZP_SrcHi
    lda #1                      ; white
    sta ZP_Tmp
    lda #8                      ; row again
    jsr CenterPrintRow

    lda #10
    lda #<Uber2
    sta ZP_SrcLo
    lda #>Uber2
    sta ZP_SrcHi
    lda #1
    sta ZP_Tmp
    lda #10
    jsr CenterPrintRow

    ; IRQ setup
    jsr IRQ_Init
    jsr InitScroller
    jsr ColorizeLogo
    cli
Forever:
    jmp Forever

; ---------------- Text ----------------
Uber1: !scr "UBER CREW"
!byte 0
Uber2: !scr "2025"
!byte 0

; ---------------- Centered row print ----------------
; In:  A=row (0..24), (ZP_SrcLo/ZP_SrcHi)=ptr to 0-terminated text, ZP_Tmp=color
CenterPrintRow:
    sta RowTmp
    ; compute length -> Len
    ldy #0
@len_loop:
    lda (ZP_SrcLo),y
    beq @got_len
    iny
    bne @len_loop
@got_len:
    sty Len

    ; startcol = (40 - len)/2  -> store in ZP_DstLo
    tya                 ; A=len
    eor #$ff
    clc
    adc #41
    lsr
    sta ZP_DstLo        ; startcol

    ; get screen row base -> ZP_DstLo/ZP_DstHi (will overwrite startcol so save it)
    pha                 ; save startcol
    tax                 ; also keep startcol in X if needed
    ldy RowTmp          ; row index for table lookups
    lda RowScrLo,y
    sta ZP_DstLo
    lda RowScrHi,y
    sta ZP_DstHi
    pla                 ; restore startcol to A

    ; advance pointer by startcol
    tax
@adv_sc:
    cpx #0
    beq @write
    inc ZP_DstLo
    bne @adv_ok
    inc ZP_DstHi
@adv_ok:
    dex
    bne @adv_sc

@write:
    ldy #0
@wloop:
    cpy Len
    beq @colors
    lda (ZP_SrcLo),y
    sta (ZP_DstLo),y
    iny
    bne @wloop

@colors:
    ; Recompute the centered color span using the preserved row index.
    lda Len
    eor #$ff
    clc
    adc #41
    lsr
    tax
    ldy RowTmp
    lda RowColLo,y
    sta ZP_DstLo
    lda RowColHi,y
    sta ZP_DstHi
@color_adv:
    cpx #0
    beq @color_write
    inc ZP_DstLo
    bne @color_ok
    inc ZP_DstHi
@color_ok:
    dex
    bne @color_adv
@color_write:
    ldy #0
@color_loop:
    cpy Len
    beq @done_colors
    lda ZP_Tmp
    sta (ZP_DstLo),y
    iny
    bne @color_loop
@done_colors:
    rts


; ---------------- Colorize logo rows with gradient ----------------
ColorizeLogo:
    ; row 8
    ldx #8
    jsr ColorizeRowGrad
    ; row 10
    ldx #10
    jsr ColorizeRowGrad
    rts

; X=row index
ColorizeRowGrad:
    lda RowColLo,x
    sta ZP_DstLo
    lda RowColHi,x
    sta ZP_DstHi
    ldy #0
@loop:
    lda LogoGrad16,y
    sta (ZP_DstLo),y
    iny
    cpy #16
    bne @loop
    ; repeat gradient across 40 cols (write 3 blocks: 16+16+8)
    ldy #16
@rep1:
    lda LogoGrad16-16,y  ; wrap from start
    sta (ZP_DstLo),y
    iny
    cpy #32
    bne @rep1
    ldy #32
@rep2:
    lda LogoGrad16-32,y
    sta (ZP_DstLo),y
    iny
    cpy #40
    bne @rep2
    rts

; ---------------- IRQ: single per frame, bars via stable waits ----------------

; ---------------- Bottom scroller (row 21) ----------------
InitScroller:
    lda #0
    sta ScrIdx
    lda #7
    sta Smooth
    ; clear row 21
    ldx #0
@cl:
    lda #$20
    sta SCREEN+21*40,x
    inx
    cpx #40
    bne @cl
    rts

Scroller_Tick:
    lda Smooth
    beq @shift
    dec Smooth
    ; set fine scroll and return
    lda Smooth
    ora #$08
    sta CTRL2
    rts
@shift:
    lda #7
    sta Smooth
    lda #$0f
    sta CTRL2
    ; shift left
    ldx #0
@mv:
    lda SCREEN+21*40+1,x
    sta SCREEN+21*40+0,x
    inx
    cpx #39
    bne @mv
    ; inject next char
    ldx ScrIdx
    lda ScrollTxt,x
    bne @ok
    ldx #0
    lda ScrollTxt,x
@ok:
    sta SCREEN+21*40+39
    inx
    stx ScrIdx
    ; color last cell
    lda #1
    sta COLOR+21*40+39
    rts

IRQ_Handler:
    lda VICIRQFLAG
    and #$01
    beq .rti

    pha
    txa : pha
    tya : pha

    ; ACK raster
    lda VICIRQFLAG
    sta VICIRQFLAG

    ; music tick + frame count
    jsr SID_Tick
    jsr Scroller_Tick
    inc FrameCount

    ; ensure MSB cleared
    lda CTRL1
    and #$7f
    sta CTRL1

    ldx #0
@nextbar:
@w1: lda RASTER
    cmp RasterLines,x
    bne @w1
@w2: lda CTRL1
    bpl @w2
    lda FrameCount
    and #$0f
    tay
    lda BarColors,y
    sta BGCOL
    lda #0
    sta BORDERCOL
    inx
    cpx #16
    bne @nextbar

    lda #48
    sta RASTER
    lda CTRL1
    and #$7f
    sta CTRL1
    lda #$01
    sta VICIRQEN

    pla : tay
    pla : tax
    pla
.rti:
    rti

IRQ_Init:
    lda VICIRQFLAG
    sta VICIRQFLAG
    lda CTRL1
    and #$7f
    sta CTRL1
    lda #48
    sta RASTER
    lda #$01
    sta VICIRQEN
    lda #<IRQ_Handler
    sta $0314
    lda #>IRQ_Handler
    sta $0315
    rts

; ---------------- SID (tiny arpeggio) ----------------
SID_Init:
    lda #$0f
    sta $d418
    lda #$11
    sta $d404
    rts

NoteLo: !byte <$11ED, <$0FEA, <$0E10
NoteHi: !byte >$11ED, >$0FEA, >$0E10
ArpSeq: !byte 0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,0

SID_Tick:
    ldx ArpIdx
    lda ArpSeq,x
    tay
    lda NoteLo,y
    sta $d400
    lda NoteHi,y
    sta $d401
    lda #$11
    sta $d404
    inx
    txa
    and #$0f
    sta ArpIdx
    rts

; ---------------- Clear helpers ----------------
ClearScreen:
    lda #$20
    ldx #0
@1: sta $0400,x
    sta $0500,x
    sta $0600,x
    inx
    bne @1
    ldx #231
@2: sta $0700,x
    dex
    bpl @2
    rts

ClearColor:
    lda #$01            ; white for readability
    ldx #0
@3: sta $d800,x
    sta $d900,x
    sta $da00,x
    inx
    bne @3
    ldx #231
@4: sta $db00,x
    dex
    bpl @4
    rts

; ===== VIC-II bank/charset hard fix =====
VIC_BankFix:
    ; Select VIC bank 0: $0000-$3FFF (bits 0-1 of $DD00 = %00)
    lda $dd00
    and #%11111100
    sta $dd00

    ; Screen = $0400, Charset = $2000 -> $d018 = $18
    lda #$18
    sta $d018
    rts


; ===== Embedded charsets (A = original, B = metallic variant) =====
; Size: 256 chars x 8 bytes = 2048 bytes each
; Place these at your desired memory (e.g., CHR A at $2000, CHR B at $2800)
!zone EmbeddedCharsets
* = $2000
Charset_A_Start:
Charset_A:
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $00
!byte $00,$00,$00,$00,$40,$00,$00,$40  ; char $01
!byte $00,$00,$00,$00,$42,$87,$07,$06  ; char $02
!byte $00,$00,$00,$00,$4d,$cf,$c5,$0f  ; char $03
!byte $00,$00,$00,$00,$0f,$9a,$0f,$95  ; char $04
!byte $00,$00,$00,$00,$bc,$26,$26,$26  ; char $05
!byte $00,$00,$00,$00,$78,$4c,$74,$40  ; char $06
!byte $00,$00,$00,$00,$80,$80,$80,$80  ; char $07
!byte $00,$00,$00,$00,$80,$80,$8f,$80  ; char $08
!byte $00,$00,$00,$00,$00,$04,$8e,$04  ; char $09
!byte $00,$00,$00,$00,$08,$10,$30,$30  ; char $0a
!byte $00,$00,$00,$00,$00,$00,$00,$20  ; char $0b
!byte $00,$00,$00,$00,$60,$a0,$61,$00  ; char $0c
!byte $00,$00,$00,$00,$00,$00,$81,$81  ; char $0d
!byte $00,$00,$00,$00,$00,$c6,$84,$06  ; char $0e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $0f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $10
!byte $00,$00,$00,$00,$70,$59,$79,$51  ; char $11
!byte $00,$00,$00,$00,$e7,$26,$e6,$26  ; char $12
!byte $00,$00,$00,$00,$87,$cc,$8c,$cd  ; char $13
!byte $1f,$00,$00,$00,$1a,$12,$12,$93  ; char $14
!byte $00,$00,$00,$00,$3e,$20,$20,$20  ; char $15
!byte $00,$00,$00,$00,$7c,$40,$40,$40  ; char $16
!byte $00,$00,$00,$00,$f3,$83,$b3,$93  ; char $17
!byte $00,$00,$00,$00,$61,$61,$61,$6d  ; char $18
!byte $00,$00,$00,$00,$8f,$82,$82,$92  ; char $19
!byte $00,$00,$00,$00,$36,$3c,$38,$34  ; char $1a
!byte $20,$00,$00,$00,$41,$41,$41,$41  ; char $1b
!byte $41,$00,$00,$00,$b3,$f3,$d3,$93  ; char $1c
!byte $83,$00,$00,$00,$63,$e6,$e6,$66  ; char $1d
!byte $00,$00,$00,$00,$c0,$c0,$c0,$c0  ; char $1e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $1f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $20
!byte $71,$00,$00,$00,$49,$49,$71,$41  ; char $21
!byte $27,$00,$00,$e4,$26,$26,$e7,$e6  ; char $22
!byte $87,$00,$00,$00,$49,$47,$81,$c9  ; char $23
!byte $1e,$00,$00,$00,$84,$04,$84,$84  ; char $24
!byte $3e,$00,$00,$00,$24,$24,$26,$26  ; char $25
!byte $40,$00,$00,$00,$48,$48,$48,$70  ; char $26
!byte $e3,$00,$00,$00,$9b,$99,$b9,$fb  ; char $27
!byte $67,$00,$00,$00,$6d,$85,$c2,$62  ; char $28
!byte $1c,$00,$00,$00,$82,$02,$0c,$08  ; char $29
!byte $36,$00,$00,$00,$36,$36,$3e,$16  ; char $2a
!byte $79,$00,$00,$00,$48,$18,$30,$28  ; char $2b
!byte $93,$00,$00,$00,$b1,$73,$13,$90  ; char $2c
!byte $63,$00,$00,$00,$c6,$46,$e6,$47  ; char $2d
!byte $80,$00,$00,$00,$00,$00,$00,$c0  ; char $2e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $2f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $30
!byte $00,$00,$00,$00,$58,$58,$78,$59  ; char $31
!byte $00,$00,$00,$00,$26,$66,$86,$f3  ; char $32
!byte $00,$00,$00,$00,$c9,$09,$49,$8f  ; char $33
!byte $00,$00,$00,$00,$8a,$9b,$9f,$1b  ; char $34
!byte $00,$00,$00,$00,$26,$26,$26,$3e  ; char $35
!byte $00,$00,$00,$08,$4c,$40,$40,$78  ; char $36
!byte $00,$00,$00,$00,$93,$93,$93,$f3  ; char $37
!byte $00,$00,$00,$00,$0c,$0c,$0c,$ec  ; char $38
!byte $00,$00,$00,$00,$13,$10,$13,$1f  ; char $39
!byte $00,$00,$00,$00,$08,$08,$08,$08  ; char $3a
!byte $00,$00,$00,$00,$30,$00,$30,$30  ; char $3b
!byte $00,$00,$00,$00,$60,$01,$e1,$80  ; char $3c
!byte $00,$00,$00,$00,$c3,$80,$81,$c2  ; char $3d
!byte $00,$00,$00,$00,$00,$8c,$8b,$00  ; char $3e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $3f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $40
!byte $00,$00,$00,$71,$d9,$19,$01,$21  ; char $41
!byte $00,$00,$00,$e6,$36,$f0,$f0,$e6  ; char $42
!byte $00,$00,$00,$4d,$4d,$0d,$0d,$4f  ; char $43
!byte $00,$00,$00,$9b,$9b,$9b,$9b,$8e  ; char $44
!byte $00,$00,$00,$26,$26,$26,$3e,$36  ; char $45
!byte $00,$00,$00,$4c,$48,$70,$58,$48  ; char $46
!byte $00,$00,$00,$92,$90,$e0,$61,$63  ; char $47
!byte $00,$00,$00,$60,$46,$8d,$06,$47  ; char $48
!byte $00,$00,$00,$0c,$04,$04,$84,$0e  ; char $49
!byte $00,$00,$00,$1c,$10,$10,$10,$1c  ; char $4a
!byte $00,$00,$00,$30,$30,$30,$31,$30  ; char $4b
!byte $00,$00,$00,$00,$00,$a3,$b3,$e1  ; char $4c
!byte $00,$00,$00,$00,$00,$c3,$c7,$c0  ; char $4d
!byte $00,$00,$00,$00,$00,$86,$87,$0f  ; char $4e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $4f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $50
!byte $00,$00,$00,$01,$21,$71,$71,$21  ; char $51
!byte $00,$00,$00,$e3,$80,$80,$80,$e3  ; char $52
!byte $00,$00,$00,$86,$86,$84,$82,$86  ; char $53
!byte $00,$00,$00,$04,$0e,$0f,$04,$04  ; char $54
!byte $00,$00,$00,$00,$10,$3c,$0c,$38  ; char $55
!byte $00,$00,$00,$00,$78,$78,$78,$30  ; char $56
!byte $00,$00,$00,$40,$f2,$f2,$f2,$63  ; char $57
!byte $00,$00,$00,$40,$44,$44,$44,$c7  ; char $58
!byte $00,$00,$00,$08,$8e,$8b,$91,$9f  ; char $59
!byte $00,$00,$00,$0e,$3e,$08,$1e,$38  ; char $5a
!byte $00,$00,$00,$00,$79,$01,$78,$48  ; char $5b
!byte $00,$00,$00,$80,$91,$b1,$e0,$20  ; char $5c
!byte $00,$00,$00,$00,$c1,$c3,$83,$83  ; char $5d
!byte $00,$00,$00,$00,$06,$86,$0f,$00  ; char $5e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $5f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $60
!byte $00,$00,$00,$79,$79,$01,$79,$79  ; char $61
!byte $00,$00,$00,$e0,$e3,$c7,$e3,$e1  ; char $62
!byte $00,$00,$00,$08,$8c,$ce,$8f,$0f  ; char $63
!byte $00,$00,$00,$00,$9e,$9f,$8e,$84  ; char $64
!byte $00,$00,$00,$00,$18,$3c,$08,$18  ; char $65
!byte $00,$00,$00,$00,$20,$78,$f8,$20  ; char $66
!byte $00,$00,$00,$40,$40,$e1,$b0,$f0  ; char $67
!byte $00,$00,$00,$00,$80,$c7,$80,$00  ; char $68
!byte $00,$00,$00,$0c,$08,$8c,$0c,$08  ; char $69
!byte $00,$00,$00,$20,$30,$38,$3c,$3e  ; char $6a
!byte $00,$00,$00,$10,$10,$10,$30,$30  ; char $6b
!byte $00,$00,$00,$00,$e0,$21,$03,$83  ; char $6c
!byte $00,$00,$00,$83,$81,$44,$42,$e1  ; char $6d
!byte $00,$00,$00,$80,$86,$8e,$08,$8f  ; char $6e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $6f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $70
!byte $00,$00,$00,$30,$78,$c0,$31,$e0  ; char $71
!byte $00,$00,$00,$a2,$62,$02,$83,$60  ; char $72
!byte $00,$00,$00,$00,$06,$8b,$89,$80  ; char $73
!byte $00,$00,$00,$04,$8e,$82,$04,$0e  ; char $74
!byte $00,$00,$00,$00,$08,$00,$00,$14  ; char $75
!byte $00,$00,$00,$00,$28,$58,$78,$00  ; char $76
!byte $00,$00,$00,$00,$00,$00,$f1,$01  ; char $77
!byte $00,$00,$00,$82,$82,$82,$82,$02  ; char $78
!byte $08,$00,$00,$00,$10,$14,$02,$00  ; char $79
!byte $00,$00,$00,$00,$00,$18,$00,$00  ; char $7a
!byte $00,$00,$00,$00,$00,$80,$fc,$00  ; char $7b
!byte $00,$00,$00,$60,$60,$40,$60,$c0  ; char $7c
!byte $00,$00,$00,$03,$82,$82,$82,$42  ; char $7d
!byte $00,$00,$00,$8e,$02,$02,$02,$03  ; char $7e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $7f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $80
!byte $00,$00,$00,$00,$00,$31,$49,$49  ; char $81
!byte $00,$00,$00,$00,$00,$e1,$92,$e2  ; char $82
!byte $00,$00,$00,$00,$00,$cf,$0d,$0d  ; char $83
!byte $00,$00,$00,$00,$00,$1f,$90,$9c  ; char $84
!byte $00,$00,$00,$00,$00,$3c,$20,$38  ; char $85
!byte $00,$00,$00,$00,$00,$73,$83,$b3  ; char $86
!byte $00,$00,$00,$00,$00,$67,$63,$e3  ; char $87
!byte $00,$00,$00,$00,$00,$83,$03,$02  ; char $88
!byte $00,$00,$00,$00,$00,$24,$28,$38  ; char $89
!byte $00,$00,$00,$00,$00,$c3,$c3,$c3  ; char $8a
!byte $00,$00,$00,$00,$00,$14,$f7,$b7  ; char $8b
!byte $00,$00,$00,$00,$00,$c7,$49,$c9  ; char $8c
!byte $00,$00,$00,$00,$00,$1e,$12,$12  ; char $8d
!byte $00,$00,$00,$00,$00,$3c,$24,$24  ; char $8e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $8f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $90
!byte $49,$49,$00,$00,$00,$78,$49,$48  ; char $91
!byte $92,$e1,$00,$00,$00,$e3,$90,$e0  ; char $92
!byte $4d,$cf,$00,$00,$00,$ed,$8d,$8d  ; char $93
!byte $90,$1f,$00,$00,$00,$93,$93,$93  ; char $94
!byte $20,$20,$00,$00,$00,$24,$24,$24  ; char $95
!byte $93,$73,$00,$00,$00,$93,$f3,$61  ; char $96
!byte $63,$67,$00,$00,$00,$6f,$60,$c3  ; char $97
!byte $1a,$8e,$00,$00,$00,$8e,$9b,$0f  ; char $98
!byte $28,$24,$00,$00,$00,$18,$18,$18  ; char $99
!byte $c3,$fb,$00,$00,$00,$30,$48,$30  ; char $9a
!byte $36,$36,$00,$00,$00,$e1,$32,$66  ; char $9b
!byte $c9,$47,$00,$00,$00,$87,$85,$8d  ; char $9c
!byte $10,$10,$00,$00,$00,$1f,$10,$1f  ; char $9d
!byte $2c,$3c,$00,$00,$00,$3c,$20,$3c  ; char $9e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $9f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $a0
!byte $58,$48,$00,$00,$00,$78,$09,$10  ; char $a1
!byte $10,$e0,$00,$00,$00,$e1,$92,$e1  ; char $a2
!byte $8d,$87,$00,$00,$00,$c0,$42,$c0  ; char $a3
!byte $9f,$04,$00,$00,$00,$00,$04,$00  ; char $a4
!byte $3c,$24,$00,$00,$00,$00,$10,$00  ; char $a5
!byte $50,$90,$00,$00,$00,$20,$f1,$60  ; char $a6
!byte $82,$87,$00,$00,$00,$00,$c3,$00  ; char $a7
!byte $1b,$8e,$00,$00,$00,$0e,$02,$04  ; char $a8
!byte $08,$1c,$00,$00,$00,$18,$10,$18  ; char $a9
!byte $20,$78,$00,$00,$00,$00,$30,$20  ; char $aa
!byte $37,$e0,$00,$00,$00,$00,$41,$03  ; char $ab
!byte $cf,$81,$00,$00,$00,$80,$87,$0d  ; char $ac
!byte $83,$0e,$00,$00,$00,$00,$80,$00  ; char $ad
!byte $24,$3c,$00,$00,$00,$00,$00,$18  ; char $ae
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $af
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $b0
!byte $31,$30,$00,$00,$00,$38,$41,$59  ; char $b1
!byte $92,$e1,$00,$00,$00,$f1,$f0,$d1  ; char $b2
!byte $42,$c0,$00,$00,$00,$c7,$c6,$c6  ; char $b3
!byte $04,$00,$00,$00,$00,$0c,$04,$04  ; char $b4
!byte $10,$00,$00,$00,$00,$00,$00,$7c  ; char $b5
!byte $f1,$40,$00,$00,$00,$00,$20,$71  ; char $b6
!byte $c3,$00,$00,$00,$00,$66,$c3,$81  ; char $b7
!byte $00,$0c,$00,$00,$00,$04,$0e,$8e  ; char $b8
!byte $08,$18,$00,$00,$00,$18,$08,$08  ; char $b9
!byte $20,$30,$00,$00,$00,$20,$11,$10  ; char $ba
!byte $43,$01,$00,$00,$00,$41,$81,$c1  ; char $bb
!byte $87,$80,$00,$00,$00,$80,$02,$07  ; char $bc
!byte $04,$0c,$00,$00,$00,$00,$0a,$14  ; char $bd
!byte $08,$10,$00,$00,$00,$00,$18,$3c  ; char $be
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $bf
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $c0
!byte $49,$00,$00,$00,$00,$38,$08,$30  ; char $c1
!byte $80,$e1,$00,$00,$00,$41,$63,$b1  ; char $c2
!byte $c2,$80,$00,$00,$00,$8f,$cf,$8f  ; char $c3
!byte $04,$00,$00,$00,$00,$9e,$9e,$9e  ; char $c4
!byte $00,$00,$00,$00,$00,$3c,$3c,$30  ; char $c5
!byte $20,$00,$00,$00,$00,$61,$f3,$73  ; char $c6
!byte $c3,$42,$00,$00,$00,$e3,$e7,$e5  ; char $c7
!byte $0e,$00,$00,$00,$00,$86,$8e,$86  ; char $c8
!byte $08,$00,$00,$00,$00,$00,$18,$3c  ; char $c9
!byte $10,$00,$00,$00,$00,$30,$30,$30  ; char $ca
!byte $e1,$00,$00,$00,$00,$81,$81,$81  ; char $cb
!byte $02,$04,$00,$00,$00,$02,$87,$8f  ; char $cc
!byte $0a,$00,$00,$00,$00,$04,$04,$84  ; char $cd
!byte $18,$00,$00,$00,$00,$18,$18,$3c  ; char $ce
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $cf
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $d0
!byte $31,$00,$00,$00,$00,$30,$78,$79  ; char $d1
!byte $91,$01,$00,$00,$00,$40,$e1,$e3  ; char $d2
!byte $8f,$81,$00,$00,$00,$82,$86,$c7  ; char $d3
!byte $9e,$1e,$00,$00,$00,$04,$1e,$98  ; char $d4
!byte $30,$30,$00,$00,$00,$00,$30,$10  ; char $d5
!byte $20,$00,$00,$00,$00,$60,$f1,$61  ; char $d6
!byte $c3,$00,$00,$00,$00,$c3,$e3,$e3  ; char $d7
!byte $84,$00,$00,$00,$00,$0e,$8a,$13  ; char $d8
!byte $00,$00,$00,$00,$00,$10,$18,$2c  ; char $d9
!byte $10,$00,$00,$00,$00,$00,$41,$10  ; char $da
!byte $01,$01,$00,$00,$00,$40,$43,$e0  ; char $db
!byte $02,$02,$00,$00,$00,$07,$c7,$47  ; char $dc
!byte $04,$00,$00,$00,$00,$0c,$0e,$1e  ; char $dd
!byte $3c,$18,$00,$00,$00,$38,$3c,$3c  ; char $de
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $df
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $e0
!byte $38,$00,$00,$00,$00,$70,$79,$79  ; char $e1
!byte $e3,$00,$00,$00,$00,$c1,$e1,$e1  ; char $e2
!byte $c2,$00,$00,$00,$00,$86,$8f,$8f  ; char $e3
!byte $00,$00,$00,$00,$00,$08,$0c,$0c  ; char $e4
!byte $00,$00,$00,$00,$00,$38,$38,$38  ; char $e5
!byte $71,$00,$00,$00,$00,$00,$61,$f1  ; char $e6
!byte $c0,$00,$00,$00,$00,$80,$e3,$c3  ; char $e7
!byte $02,$00,$00,$00,$00,$04,$0a,$0a  ; char $e8
!byte $24,$00,$00,$00,$00,$00,$1c,$18  ; char $e9
!byte $18,$00,$00,$00,$00,$30,$78,$78  ; char $ea
!byte $43,$00,$00,$00,$00,$41,$e3,$41  ; char $eb
!byte $c7,$00,$00,$00,$00,$00,$83,$07  ; char $ec
!byte $8c,$00,$00,$00,$00,$04,$02,$8a  ; char $ed
!byte $30,$00,$00,$00,$00,$3c,$08,$00  ; char $ee
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $ef
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $f0
!byte $30,$00,$00,$00,$00,$00,$00,$00  ; char $f1
!byte $41,$00,$00,$00,$00,$00,$00,$00  ; char $f2
!byte $82,$00,$00,$00,$00,$00,$00,$00  ; char $f3
!byte $0c,$00,$00,$00,$00,$00,$00,$00  ; char $f4
!byte $38,$00,$00,$00,$00,$00,$00,$00  ; char $f5
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $f6
!byte $87,$00,$00,$00,$00,$00,$00,$00  ; char $f7
!byte $86,$00,$00,$00,$00,$00,$00,$00  ; char $f8
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $f9
!byte $30,$00,$00,$00,$00,$00,$00,$00  ; char $fa
!byte $c1,$00,$00,$00,$00,$00,$00,$00  ; char $fb
!byte $02,$00,$00,$00,$00,$00,$00,$00  ; char $fc
!byte $0f,$00,$00,$00,$00,$00,$00,$00  ; char $fd
!byte $18,$00,$00,$00,$00,$00,$00,$00  ; char $fe
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $ff
Charset_A_End:

* = $2800
Charset_B_Start:
Charset_B:
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $00
!byte $00,$00,$00,$00,$40,$00,$00,$40  ; char $01
!byte $00,$00,$00,$00,$42,$87,$07,$07  ; char $02
!byte $00,$00,$00,$00,$4d,$cf,$c5,$cf  ; char $03
!byte $00,$00,$00,$00,$0f,$9a,$0f,$9f  ; char $04
!byte $00,$00,$00,$00,$bc,$26,$26,$26  ; char $05
!byte $00,$00,$00,$00,$78,$4c,$74,$74  ; char $06
!byte $00,$00,$00,$00,$80,$80,$80,$80  ; char $07
!byte $00,$00,$00,$00,$80,$80,$8f,$8f  ; char $08
!byte $00,$00,$00,$00,$00,$04,$8e,$8e  ; char $09
!byte $00,$00,$00,$00,$08,$10,$30,$30  ; char $0a
!byte $00,$00,$00,$00,$00,$00,$00,$20  ; char $0b
!byte $00,$00,$00,$00,$60,$a0,$61,$61  ; char $0c
!byte $00,$00,$00,$00,$00,$00,$81,$81  ; char $0d
!byte $00,$00,$00,$00,$00,$c6,$84,$86  ; char $0e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $0f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $10
!byte $00,$00,$00,$00,$70,$59,$79,$79  ; char $11
!byte $00,$00,$00,$00,$e7,$26,$e6,$e6  ; char $12
!byte $00,$00,$00,$00,$87,$cc,$8c,$cd  ; char $13
!byte $1f,$00,$00,$00,$1a,$12,$12,$93  ; char $14
!byte $00,$00,$00,$00,$3e,$20,$20,$20  ; char $15
!byte $00,$00,$00,$00,$7c,$40,$40,$40  ; char $16
!byte $00,$00,$00,$00,$f3,$83,$b3,$b3  ; char $17
!byte $00,$00,$00,$00,$61,$61,$61,$6d  ; char $18
!byte $00,$00,$00,$00,$8f,$82,$82,$92  ; char $19
!byte $00,$00,$00,$00,$36,$3c,$38,$3c  ; char $1a
!byte $20,$00,$00,$00,$41,$41,$41,$41  ; char $1b
!byte $41,$00,$00,$00,$b3,$f3,$d3,$d3  ; char $1c
!byte $83,$00,$00,$00,$63,$e6,$e6,$e6  ; char $1d
!byte $00,$00,$00,$00,$c0,$c0,$c0,$c0  ; char $1e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $1f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $20
!byte $71,$00,$00,$00,$49,$49,$71,$71  ; char $21
!byte $27,$00,$00,$e4,$26,$26,$e7,$e7  ; char $22
!byte $87,$00,$00,$00,$49,$47,$81,$c9  ; char $23
!byte $1e,$00,$00,$00,$84,$04,$84,$84  ; char $24
!byte $3e,$00,$00,$00,$24,$24,$26,$26  ; char $25
!byte $40,$00,$00,$00,$48,$48,$48,$78  ; char $26
!byte $e3,$00,$00,$00,$9b,$99,$b9,$fb  ; char $27
!byte $67,$00,$00,$00,$6d,$85,$c2,$e2  ; char $28
!byte $1c,$00,$00,$00,$82,$02,$0c,$0c  ; char $29
!byte $36,$00,$00,$00,$36,$36,$3e,$3e  ; char $2a
!byte $79,$00,$00,$00,$48,$18,$30,$38  ; char $2b
!byte $93,$00,$00,$00,$b1,$73,$13,$93  ; char $2c
!byte $63,$00,$00,$00,$c6,$46,$e6,$e7  ; char $2d
!byte $80,$00,$00,$00,$00,$00,$00,$c0  ; char $2e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $2f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $30
!byte $00,$00,$00,$00,$58,$58,$78,$79  ; char $31
!byte $00,$00,$00,$00,$26,$66,$86,$f7  ; char $32
!byte $00,$00,$00,$00,$c9,$09,$49,$cf  ; char $33
!byte $00,$00,$00,$00,$8a,$9b,$9f,$9f  ; char $34
!byte $00,$00,$00,$00,$26,$26,$26,$3e  ; char $35
!byte $00,$00,$00,$08,$4c,$40,$40,$78  ; char $36
!byte $00,$00,$00,$00,$93,$93,$93,$f3  ; char $37
!byte $00,$00,$00,$00,$0c,$0c,$0c,$ec  ; char $38
!byte $00,$00,$00,$00,$13,$10,$13,$1f  ; char $39
!byte $00,$00,$00,$00,$08,$08,$08,$08  ; char $3a
!byte $00,$00,$00,$00,$30,$00,$30,$30  ; char $3b
!byte $00,$00,$00,$00,$60,$01,$e1,$e1  ; char $3c
!byte $00,$00,$00,$00,$c3,$80,$81,$c3  ; char $3d
!byte $00,$00,$00,$00,$00,$8c,$8b,$8b  ; char $3e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $3f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $40
!byte $00,$00,$00,$71,$d9,$19,$01,$21  ; char $41
!byte $00,$00,$00,$e6,$36,$f0,$f0,$f6  ; char $42
!byte $00,$00,$00,$4d,$4d,$0d,$0d,$4f  ; char $43
!byte $00,$00,$00,$9b,$9b,$9b,$9b,$9f  ; char $44
!byte $00,$00,$00,$26,$26,$26,$3e,$3e  ; char $45
!byte $00,$00,$00,$4c,$48,$70,$58,$58  ; char $46
!byte $00,$00,$00,$92,$90,$e0,$61,$63  ; char $47
!byte $00,$00,$00,$60,$46,$8d,$06,$47  ; char $48
!byte $00,$00,$00,$0c,$04,$04,$84,$8e  ; char $49
!byte $00,$00,$00,$1c,$10,$10,$10,$1c  ; char $4a
!byte $00,$00,$00,$30,$30,$30,$31,$31  ; char $4b
!byte $00,$00,$00,$00,$00,$a3,$b3,$f3  ; char $4c
!byte $00,$00,$00,$00,$00,$c3,$c7,$c7  ; char $4d
!byte $00,$00,$00,$00,$00,$86,$87,$8f  ; char $4e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $4f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $50
!byte $00,$00,$00,$01,$21,$71,$71,$71  ; char $51
!byte $00,$00,$00,$e3,$80,$80,$80,$e3  ; char $52
!byte $00,$00,$00,$86,$86,$84,$82,$86  ; char $53
!byte $00,$00,$00,$04,$0e,$0f,$04,$04  ; char $54
!byte $00,$00,$00,$00,$10,$3c,$0c,$3c  ; char $55
!byte $00,$00,$00,$00,$78,$78,$78,$78  ; char $56
!byte $00,$00,$00,$40,$f2,$f2,$f2,$f3  ; char $57
!byte $00,$00,$00,$40,$44,$44,$44,$c7  ; char $58
!byte $00,$00,$00,$08,$8e,$8b,$91,$9f  ; char $59
!byte $00,$00,$00,$0e,$3e,$08,$1e,$3e  ; char $5a
!byte $00,$00,$00,$00,$79,$01,$78,$78  ; char $5b
!byte $00,$00,$00,$80,$91,$b1,$e0,$e0  ; char $5c
!byte $00,$00,$00,$00,$c1,$c3,$83,$83  ; char $5d
!byte $00,$00,$00,$00,$06,$86,$0f,$0f  ; char $5e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $5f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $60
!byte $00,$00,$00,$79,$79,$01,$79,$79  ; char $61
!byte $00,$00,$00,$e0,$e3,$c7,$e3,$e3  ; char $62
!byte $00,$00,$00,$08,$8c,$ce,$8f,$8f  ; char $63
!byte $00,$00,$00,$00,$9e,$9f,$8e,$8e  ; char $64
!byte $00,$00,$00,$00,$18,$3c,$08,$18  ; char $65
!byte $00,$00,$00,$00,$20,$78,$f8,$f8  ; char $66
!byte $00,$00,$00,$40,$40,$e1,$b0,$f0  ; char $67
!byte $00,$00,$00,$00,$80,$c7,$80,$80  ; char $68
!byte $00,$00,$00,$0c,$08,$8c,$0c,$0c  ; char $69
!byte $00,$00,$00,$20,$30,$38,$3c,$3e  ; char $6a
!byte $00,$00,$00,$10,$10,$10,$30,$30  ; char $6b
!byte $00,$00,$00,$00,$e0,$21,$03,$83  ; char $6c
!byte $00,$00,$00,$83,$81,$44,$42,$e3  ; char $6d
!byte $00,$00,$00,$80,$86,$8e,$08,$8f  ; char $6e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $6f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $70
!byte $00,$00,$00,$30,$78,$c0,$31,$f1  ; char $71
!byte $00,$00,$00,$a2,$62,$02,$83,$e3  ; char $72
!byte $00,$00,$00,$00,$06,$8b,$89,$89  ; char $73
!byte $00,$00,$00,$04,$8e,$82,$04,$0e  ; char $74
!byte $00,$00,$00,$00,$08,$00,$00,$14  ; char $75
!byte $00,$00,$00,$00,$28,$58,$78,$78  ; char $76
!byte $00,$00,$00,$00,$00,$00,$f1,$f1  ; char $77
!byte $00,$00,$00,$82,$82,$82,$82,$82  ; char $78
!byte $08,$00,$00,$00,$10,$14,$02,$02  ; char $79
!byte $00,$00,$00,$00,$00,$18,$00,$00  ; char $7a
!byte $00,$00,$00,$00,$00,$80,$fc,$fc  ; char $7b
!byte $00,$00,$00,$60,$60,$40,$60,$e0  ; char $7c
!byte $00,$00,$00,$03,$82,$82,$82,$c2  ; char $7d
!byte $00,$00,$00,$8e,$02,$02,$02,$03  ; char $7e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $7f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $80
!byte $00,$00,$00,$00,$00,$31,$49,$49  ; char $81
!byte $00,$00,$00,$00,$00,$e1,$92,$f2  ; char $82
!byte $00,$00,$00,$00,$00,$cf,$0d,$0d  ; char $83
!byte $00,$00,$00,$00,$00,$1f,$90,$9c  ; char $84
!byte $00,$00,$00,$00,$00,$3c,$20,$38  ; char $85
!byte $00,$00,$00,$00,$00,$73,$83,$b3  ; char $86
!byte $00,$00,$00,$00,$00,$67,$63,$e3  ; char $87
!byte $00,$00,$00,$00,$00,$83,$03,$03  ; char $88
!byte $00,$00,$00,$00,$00,$24,$28,$38  ; char $89
!byte $00,$00,$00,$00,$00,$c3,$c3,$c3  ; char $8a
!byte $00,$00,$00,$00,$00,$14,$f7,$f7  ; char $8b
!byte $00,$00,$00,$00,$00,$c7,$49,$c9  ; char $8c
!byte $00,$00,$00,$00,$00,$1e,$12,$12  ; char $8d
!byte $00,$00,$00,$00,$00,$3c,$24,$24  ; char $8e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $8f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $90
!byte $49,$49,$00,$00,$00,$78,$49,$49  ; char $91
!byte $f3,$e1,$00,$00,$00,$e3,$90,$f0  ; char $92
!byte $cf,$cf,$00,$00,$00,$ed,$8d,$8d  ; char $93
!byte $9f,$1f,$00,$00,$00,$93,$93,$93  ; char $94
!byte $20,$20,$00,$00,$00,$24,$24,$24  ; char $95
!byte $f3,$73,$00,$00,$00,$93,$f3,$f3  ; char $96
!byte $67,$67,$00,$00,$00,$6f,$60,$e3  ; char $97
!byte $9e,$8e,$00,$00,$00,$8e,$9b,$9f  ; char $98
!byte $2c,$24,$00,$00,$00,$18,$18,$18  ; char $99
!byte $fb,$fb,$00,$00,$00,$30,$48,$78  ; char $9a
!byte $36,$36,$00,$00,$00,$e1,$32,$76  ; char $9b
!byte $cf,$47,$00,$00,$00,$87,$85,$8d  ; char $9c
!byte $10,$10,$00,$00,$00,$1f,$10,$1f  ; char $9d
!byte $3c,$3c,$00,$00,$00,$3c,$20,$3c  ; char $9e
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $9f
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $a0
!byte $58,$48,$00,$00,$00,$78,$09,$19  ; char $a1
!byte $f0,$e0,$00,$00,$00,$e1,$92,$f3  ; char $a2
!byte $8f,$87,$00,$00,$00,$c0,$42,$c2  ; char $a3
!byte $9f,$04,$00,$00,$00,$00,$04,$04  ; char $a4
!byte $3c,$24,$00,$00,$00,$00,$10,$10  ; char $a5
!byte $d0,$90,$00,$00,$00,$20,$f1,$f1  ; char $a6
!byte $87,$87,$00,$00,$00,$00,$c3,$c3  ; char $a7
!byte $9f,$8e,$00,$00,$00,$0e,$02,$06  ; char $a8
!byte $1c,$1c,$00,$00,$00,$18,$10,$18  ; char $a9
!byte $78,$78,$00,$00,$00,$00,$30,$30  ; char $aa
!byte $f7,$e0,$00,$00,$00,$00,$41,$43  ; char $ab
!byte $cf,$81,$00,$00,$00,$80,$87,$8f  ; char $ac
!byte $8f,$0e,$00,$00,$00,$00,$80,$80  ; char $ad
!byte $3c,$3c,$00,$00,$00,$00,$00,$18  ; char $ae
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $af
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $b0
!byte $31,$30,$00,$00,$00,$38,$41,$59  ; char $b1
!byte $f3,$e1,$00,$00,$00,$f1,$f0,$f1  ; char $b2
!byte $c2,$c0,$00,$00,$00,$c7,$c6,$c6  ; char $b3
!byte $04,$00,$00,$00,$00,$0c,$04,$04  ; char $b4
!byte $10,$00,$00,$00,$00,$00,$00,$7c  ; char $b5
!byte $f1,$40,$00,$00,$00,$00,$20,$71  ; char $b6
!byte $c3,$00,$00,$00,$00,$66,$c3,$c3  ; char $b7
!byte $0c,$0c,$00,$00,$00,$04,$0e,$8e  ; char $b8
!byte $18,$18,$00,$00,$00,$18,$08,$08  ; char $b9
!byte $30,$30,$00,$00,$00,$20,$11,$11  ; char $ba
!byte $43,$01,$00,$00,$00,$41,$81,$c1  ; char $bb
!byte $87,$80,$00,$00,$00,$80,$02,$07  ; char $bc
!byte $0c,$0c,$00,$00,$00,$00,$0a,$1e  ; char $bd
!byte $18,$10,$00,$00,$00,$00,$18,$3c  ; char $be
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $bf
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $c0
!byte $49,$00,$00,$00,$00,$38,$08,$38  ; char $c1
!byte $e1,$e1,$00,$00,$00,$41,$63,$f3  ; char $c2
!byte $c2,$80,$00,$00,$00,$8f,$cf,$cf  ; char $c3
!byte $04,$00,$00,$00,$00,$9e,$9e,$9e  ; char $c4
!byte $00,$00,$00,$00,$00,$3c,$3c,$3c  ; char $c5
!byte $20,$00,$00,$00,$00,$61,$f3,$f3  ; char $c6
!byte $c3,$42,$00,$00,$00,$e3,$e7,$e7  ; char $c7
!byte $0e,$00,$00,$00,$00,$86,$8e,$8e  ; char $c8
!byte $08,$00,$00,$00,$00,$00,$18,$3c  ; char $c9
!byte $10,$00,$00,$00,$00,$30,$30,$30  ; char $ca
!byte $e1,$00,$00,$00,$00,$81,$81,$81  ; char $cb
!byte $06,$04,$00,$00,$00,$02,$87,$8f  ; char $cc
!byte $0a,$00,$00,$00,$00,$04,$04,$84  ; char $cd
!byte $18,$00,$00,$00,$00,$18,$18,$3c  ; char $ce
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $cf
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $d0
!byte $31,$00,$00,$00,$00,$30,$78,$79  ; char $d1
!byte $91,$01,$00,$00,$00,$40,$e1,$e3  ; char $d2
!byte $8f,$81,$00,$00,$00,$82,$86,$c7  ; char $d3
!byte $9e,$1e,$00,$00,$00,$04,$1e,$9e  ; char $d4
!byte $30,$30,$00,$00,$00,$00,$30,$30  ; char $d5
!byte $20,$00,$00,$00,$00,$60,$f1,$f1  ; char $d6
!byte $c3,$00,$00,$00,$00,$c3,$e3,$e3  ; char $d7
!byte $84,$00,$00,$00,$00,$0e,$8a,$9b  ; char $d8
!byte $00,$00,$00,$00,$00,$10,$18,$3c  ; char $d9
!byte $10,$00,$00,$00,$00,$00,$41,$51  ; char $da
!byte $01,$01,$00,$00,$00,$40,$43,$e3  ; char $db
!byte $02,$02,$00,$00,$00,$07,$c7,$c7  ; char $dc
!byte $04,$00,$00,$00,$00,$0c,$0e,$1e  ; char $dd
!byte $3c,$18,$00,$00,$00,$38,$3c,$3c  ; char $de
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $df
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $e0
!byte $38,$00,$00,$00,$00,$70,$79,$79  ; char $e1
!byte $e3,$00,$00,$00,$00,$c1,$e1,$e1  ; char $e2
!byte $c2,$00,$00,$00,$00,$86,$8f,$8f  ; char $e3
!byte $00,$00,$00,$00,$00,$08,$0c,$0c  ; char $e4
!byte $00,$00,$00,$00,$00,$38,$38,$38  ; char $e5
!byte $71,$00,$00,$00,$00,$00,$61,$f1  ; char $e6
!byte $c0,$00,$00,$00,$00,$80,$e3,$e3  ; char $e7
!byte $02,$00,$00,$00,$00,$04,$0a,$0a  ; char $e8
!byte $24,$00,$00,$00,$00,$00,$1c,$1c  ; char $e9
!byte $18,$00,$00,$00,$00,$30,$78,$78  ; char $ea
!byte $43,$00,$00,$00,$00,$41,$e3,$e3  ; char $eb
!byte $c7,$00,$00,$00,$00,$00,$83,$87  ; char $ec
!byte $8c,$00,$00,$00,$00,$04,$02,$8a  ; char $ed
!byte $30,$00,$00,$00,$00,$3c,$08,$08  ; char $ee
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $ef
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $f0
!byte $30,$00,$00,$00,$00,$00,$00,$00  ; char $f1
!byte $41,$00,$00,$00,$00,$00,$00,$00  ; char $f2
!byte $82,$00,$00,$00,$00,$00,$00,$00  ; char $f3
!byte $0c,$00,$00,$00,$00,$00,$00,$00  ; char $f4
!byte $38,$00,$00,$00,$00,$00,$00,$00  ; char $f5
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $f6
!byte $87,$00,$00,$00,$00,$00,$00,$00  ; char $f7
!byte $86,$00,$00,$00,$00,$00,$00,$00  ; char $f8
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $f9
!byte $30,$00,$00,$00,$00,$00,$00,$00  ; char $fa
!byte $c1,$00,$00,$00,$00,$00,$00,$00  ; char $fb
!byte $02,$00,$00,$00,$00,$00,$00,$00  ; char $fc
!byte $0f,$00,$00,$00,$00,$00,$00,$00  ; char $fd
!byte $18,$00,$00,$00,$00,$00,$00,$00  ; char $fe
!byte $00,$00,$00,$00,$00,$00,$00,$00  ; char $ff
Charset_B_End:
; ===== End embedded charsets =====
; (removed !end for ACME)
