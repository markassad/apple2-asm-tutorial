*--------------------------------------
* FILL.S
*
* Tutorial stage 2.  Fills every row of
* the 40x24 text page with a different
* letter -- row 0 is all 'A', row 1 is
* all 'B', etc.  The point is to write
* directly to screen memory via BASCALC
* and (BASL),Y, and watch the result
* land in row-major order even though
* the underlying memory layout is wildly
* non-linear.
*
* Build: make PROGRAM=FILL run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   FILL

HOME        EQU   $FC58
BASCALC     EQU   $FBC1

BASL        EQU   $28
BASH        EQU   $29
ROW         EQU   $E0
CHAR        EQU   $E1

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START       JSR   HOME
            LDA   #0
            STA   ROW

:ROWLOOP    LDA   ROW
            CLC
            ADC   #'A'         ;char for this row = 'A' + row index
            ORA   #$80         ;force normal display attribute
            STA   CHAR
            LDA   ROW
            JSR   BASCALC      ;sets BASL,BASH to row base
            LDA   CHAR
            LDY   #0
:COLLOOP    STA   (BASL),Y     ;write char into (row, col)
            INY
            CPY   #40
            BNE   :COLLOOP
            INC   ROW
            LDA   ROW
            CMP   #24
            BNE   :ROWLOOP

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT
