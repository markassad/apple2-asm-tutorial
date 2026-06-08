*--------------------------------------
* BENCH.S
*
* Tutorial stage 11.  Fills the text
* screen using a precomputed row-base
* table instead of calling BASCALC.  See
* the README for the cycle-count
* comparison.
*
* Build: make PROGRAM=BENCH run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   BENCH

HOME        EQU   $FC58
BASL        EQU   $28
BASH        EQU   $29

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START       JSR   HOME

* Fill the 40x24 text page with '*' using the lookup table.
* Per-row cost: ~30 cycles (table loads + 40 stores + branches),
* vs ~60 cycles using BASCALC.  See README for the breakdown.
            LDX   #0
:RL         LDA   ROW_LO,X
            STA   BASL
            LDA   ROW_HI,X
            STA   BASH
            LDY   #0
            LDA   #'*'+$80
:CL         STA   (BASL),Y
            INY
            CPY   #40
            BNE   :CL
            INX
            CPX   #24
            BNE   :RL

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* ROW_LO / ROW_HI: precomputed text row
* base addresses.  ROW_LO[r] is the low
* byte of row r's start address; ROW_HI
* is the high byte.
*
* This is what BASCALC computes on each
* call.  Trading 48 bytes of ROM-style
* table for ~30 cycles per row saved.
*--------------------------------------
ROW_LO      DFB   $00,$80,$00,$80,$00,$80,$00,$80
            DFB   $28,$A8,$28,$A8,$28,$A8,$28,$A8
            DFB   $50,$D0,$50,$D0,$50,$D0,$50,$D0
ROW_HI      DFB   $04,$04,$05,$05,$06,$06,$07,$07
            DFB   $04,$04,$05,$05,$06,$06,$07,$07
            DFB   $04,$04,$05,$05,$06,$06,$07,$07
