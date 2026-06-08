*--------------------------------------
* WALKER.S
*
* Tutorial stage 6.  An '@' you can move
* around the text screen with the arrow
* keys.  ESC quits.  Row 23 shows a hex
* step counter that ticks on every move.
*
* The whole point is the keyboard
* dispatcher: poll $C000 for input,
* clear the strobe with $C010, then
* CMP against the IIe arrow-key codes
* and dispatch to a per-direction
* handler.
*
* Build: make PROGRAM=WALKER run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   WALKER

HOME        EQU   $FC58
BASCALC     EQU   $FBC1

BASL        EQU   $28
COL         EQU   $E0
ROW         EQU   $E1
OLD_COL     EQU   $E2
OLD_ROW     EQU   $E3
STEPS       EQU   $E4

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

* IIe arrow-key codes, with the high bit set (as $C000 returns them)
K_LEFT      EQU   $88
K_RIGHT     EQU   $95
K_UP        EQU   $8B
K_DOWN      EQU   $8A
K_ESC       EQU   $9B

* Playfield: rows 0..22 (row 23 reserved for status)
MAX_ROW     EQU   22
MAX_COL     EQU   39

START       JSR   HOME

* Print "STEPS: $" on row 23
            LDA   #23
            JSR   BASCALC
            LDY   #0
            LDX   #0
:LL         LDA   LABEL,X
            BEQ   :LD
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :LL
:LD
            LDA   #20
            STA   COL
            LDA   #12
            STA   ROW
            LDA   #0
            STA   STEPS

*--------------------------------------
* Main loop
*--------------------------------------
:LOOP       LDA   ROW
            JSR   BASCALC
            LDY   COL
            LDA   #'@'+$80
            STA   (BASL),Y
            JSR   SHOW_STEPS

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB

            CMP   #K_ESC
            BEQ   :QUIT

* Save the current position so we can erase it later
            LDX   COL
            STX   OLD_COL
            LDX   ROW
            STX   OLD_ROW

* Dispatch on key.  Unknown keys fall through to :WAIT.
            CMP   #K_LEFT
            BEQ   :L
            CMP   #K_RIGHT
            BEQ   :R
            CMP   #K_UP
            BEQ   :U
            CMP   #K_DOWN
            BEQ   :D
            JMP   :WAIT

:L          LDX   COL
            BEQ   :WAIT
            DEC   COL
            JMP   :MOVED
:R          LDX   COL
            CPX   #MAX_COL
            BEQ   :WAIT
            INC   COL
            JMP   :MOVED
:U          LDX   ROW
            BEQ   :WAIT
            DEC   ROW
            JMP   :MOVED
:D          LDX   ROW
            CPX   #MAX_ROW
            BEQ   :WAIT
            INC   ROW

:MOVED      LDA   OLD_ROW
            JSR   BASCALC
            LDY   OLD_COL
            LDA   #' '+$80
            STA   (BASL),Y
            LDA   STEPS
            CMP   #$FF
            BEQ   :NOI
            INC   STEPS
:NOI        JMP   :LOOP

:QUIT       JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* SHOW_STEPS -- print STEPS as two hex
* digits at row 23, cols 8 and 9.
* Uses the JSR/fall-through trick:
* PRINT_NIB's RTS pops back to whoever
* called SHOW_STEPS.
*--------------------------------------
SHOW_STEPS  LDA   #23
            JSR   BASCALC
            LDY   #8
            LDA   STEPS
            PHA
            LSR
            LSR
            LSR
            LSR
            JSR   PRINT_NIB
            PLA
            AND   #$0F
* Fall through into PRINT_NIB; its RTS returns to SHOW_STEPS' caller.

PRINT_NIB   ORA   #$30          ;'0'..'9'
            CMP   #$3A
            BCC   :OUT
            CLC
            ADC   #6             ;'A'..'F'
:OUT        ORA   #$80
            STA   (BASL),Y
            INY
            RTS

LABEL       ASC   "STEPS: $"
            DFB   $00
