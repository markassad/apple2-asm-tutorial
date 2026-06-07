*--------------------------------------
* BOUNCE.SYSTEM
*
* Auto-running ProDOS SYS file demo.
* Clears the text screen, prints a quit
* hint on row 0, then bounces a string
* diagonally around the 40x24 text page,
* reversing direction at each edge.
* Press any key to clear the screen and
* reboot the disk.
*
* Demonstrates:
*   - BASCALC for the interleaved row
*     address layout of the text page
*   - Direct screen-memory writes via
*     (BASL),Y instead of COUT
*   - A simple per-frame delay loop
*   - Keyboard polling on $C000/$C010
*
* Build target: ProDOS SYS, type $FF,
* aux $2000.
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   BOUNCE

* Apple II monitor routines
HOME        EQU   $FC58
BASCALC     EQU   $FBC1

* Zero page used by BASCALC + ours
BASL        EQU   $28
BASH        EQU   $29
ROW         EQU   $E0
COL         EQU   $E1
DROW        EQU   $E2
DCOL        EQU   $E3

* Hardware
KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

* Layout
MSGLEN      EQU   17
MINROW      EQU   2
MAXROW      EQU   23
MAXCOL      EQU   23           ;40 - MSGLEN

*--------------------------------------
* Entry point
*--------------------------------------
START       JSR   HOME
            JSR   SHOWTITLE
            LDA   #MINROW
            STA   ROW
            LDA   #0
            STA   COL
            LDA   #1
            STA   DROW
            STA   DCOL

LOOP        JSR   ERASE
            JSR   BOUNCE
            JSR   DRAW
            JSR   DELAY
            LDA   KBD
            BPL   LOOP
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* SHOWTITLE -- print quit hint on row 0
*--------------------------------------
SHOWTITLE   LDA   #0
            JSR   BASCALC
            LDY   #10          ;(40 - 20) / 2
            LDX   #0
:TLOOP      LDA   TITLE,X
            BEQ   :TDONE
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :TLOOP
:TDONE      RTS

*--------------------------------------
* DRAW -- write MSG at (COL, ROW)
*--------------------------------------
DRAW        LDA   ROW
            JSR   BASCALC
            LDY   COL
            LDX   #0
:DLOOP      LDA   MSG,X
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            CPX   #MSGLEN
            BNE   :DLOOP
            RTS

*--------------------------------------
* ERASE -- fill MSGLEN columns at (COL, ROW) with spaces
*--------------------------------------
ERASE       LDA   ROW
            JSR   BASCALC
            LDY   COL
            LDX   #MSGLEN
:ELOOP      LDA   #$A0
            STA   (BASL),Y
            INY
            DEX
            BNE   :ELOOP
            RTS

*--------------------------------------
* BOUNCE -- step (COL,ROW) by (DCOL,DROW), reverse on edges
*
* Carry-flag check after the add catches both wrap-around
* below 0 (X becomes $FF, >= MAXCOL+1) and overshoot past
* the upper bound.  For the row we still need the MINROW
* check explicitly since MINROW > 0.
*--------------------------------------
BOUNCE      LDA   COL
            CLC
            ADC   DCOL
            TAX
            CPX   #MAXCOL+1
            BCS   :HFLIP
            STX   COL
            JMP   :HDONE
:HFLIP      LDA   #0
            SEC
            SBC   DCOL
            STA   DCOL
            LDA   COL
            CLC
            ADC   DCOL
            STA   COL

:HDONE      LDA   ROW
            CLC
            ADC   DROW
            TAX
            CPX   #MAXROW+1
            BCS   :VFLIP
            CPX   #MINROW
            BCC   :VFLIP
            STX   ROW
            RTS
:VFLIP      LDA   #0
            SEC
            SBC   DROW
            STA   DROW
            LDA   ROW
            CLC
            ADC   DROW
            STA   ROW
            RTS

*--------------------------------------
* DELAY -- ~60 ms wait, ~16 fps
*--------------------------------------
DELAY       LDY   #$30
:DOUTER     LDX   #$FF
:DINNER     DEX
            BNE   :DINNER
            DEY
            BNE   :DOUTER
            RTS

TITLE       ASC   "PRESS A KEY TO QUIT"
            DFB   $00

MSG         ASC   "HELLO, APPLE IIE!"
