*--------------------------------------
* MULT.S
*
* Tutorial stage 3.  Prints an 8x8
* multiplication table on the text page.
*
* The point isn't to admire the table --
* it's to see five 6502 addressing modes
* and a handful of looping idioms used
* in close quarters: absolute-indexed
* table reads, zero-page indexed loop
* counters, indirect-indexed screen
* writes, immediate compares, and back-
* and-forth between A, X, and Y.
*
* Build: make PROGRAM=MULT run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   MULT

HOME        EQU   $FC58
BASCALC     EQU   $FBC1

BASL        EQU   $28
ROW         EQU   $E0
COL         EQU   $E1
ONES        EQU   $E2          ;ones digit after divide by 10
TENS        EQU   $E3          ;tens digit after divide by 10

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START       JSR   HOME

* Title on row 0, centered at column 8
            LDA   #0
            JSR   BASCALC
            LDY   #8
            LDX   #0
:TLOOP      LDA   TITLE,X        ;absolute-indexed (X)
            BEQ   :TDONE
            ORA   #$80
            STA   (BASL),Y       ;indirect-indexed (Y)
            INY
            INX
            BNE   :TLOOP

:TDONE      LDA   #1
            STA   ROW

:ROWLOOP    LDA   ROW
            CLC
            ADC   #1             ;screen row = ROW + 1 (rows 2..9)
            JSR   BASCALC

            LDA   ROW
            CLC
            ADC   #'0'
            ORA   #$80
            LDY   #0
            STA   (BASL),Y       ;"R" digit at col 0
            INY
            LDA   #':'+$80
            STA   (BASL),Y       ;':' at col 1

            LDA   #1
            STA   COL
:COLLOOP

* Compute product = ROW * COL by repeated addition.
* A starts at 0 and we add ROW to it COL times.
            LDA   #0
            LDX   COL
:MULLOOP    CLC
            ADC   ROW
            DEX
            BNE   :MULLOOP

* Divide product by 10 by repeated subtraction.
* X counts the tens, A drops down to the ones.
            LDX   #0
:DIVLOOP    CMP   #10
            BCC   :DIVDONE
            SEC
            SBC   #10
            INX
            JMP   :DIVLOOP
:DIVDONE    STA   ONES
            STX   TENS

* Cell screen column = 3*COL - 1.
*   COL=1 -> Y=2     (cells start at col 2 to leave space for "R:")
*   COL=8 -> Y=23
            LDA   COL
            ASL                  ;A = 2*COL
            CLC
            ADC   COL            ;A = 3*COL
            SEC
            SBC   #1             ;A = 3*COL - 1
            TAY

            LDA   #' '+$80       ;cell padding
            STA   (BASL),Y
            INY
            LDA   TENS
            BEQ   :TBLANK        ;single digit -> tens position is blank
            CLC
            ADC   #'0'
            ORA   #$80
            JMP   :TSTORE
:TBLANK     LDA   #' '+$80
:TSTORE     STA   (BASL),Y
            INY
            LDA   ONES
            CLC
            ADC   #'0'
            ORA   #$80
            STA   (BASL),Y

            INC   COL
            LDA   COL
            CMP   #9
            BNE   :COLLOOP

            INC   ROW
            LDA   ROW
            CMP   #9
            BNE   :ROWLOOP

* Footer on row 11
            LDA   #11
            JSR   BASCALC
            LDY   #10
            LDX   #0
:FLOOP      LDA   FOOTER,X
            BEQ   :FDONE
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :FLOOP

:FDONE      LDA   KBD
            BPL   :FDONE
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT

TITLE       ASC   "MULTIPLICATION TABLE 1-8"
            DFB   $00
FOOTER      ASC   "PRESS A KEY TO QUIT"
            DFB   $00
