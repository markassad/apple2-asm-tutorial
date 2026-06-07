*--------------------------------------
* PRINTAT.S
*
* Tutorial stage 4.  Demonstrates JSR /
* RTS and a reusable PRINTAT subroutine
* that the main program calls eight
* times in a row to build a mock menu
* screen.  The whole point is that the
* same 17-byte subroutine handles every
* string regardless of position.
*
* Calling convention (zero page):
*   P_ROW  = row index (0..23)
*   P_COL  = column index (0..39)
*   P_PTR  = 16-bit pointer to a null-
*            terminated message
* PRINTAT trashes A, X, Y, BASL, BASH.
*
* Build: make PROGRAM=PRINTAT run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   PRINTAT

HOME        EQU   $FC58
BASCALC     EQU   $FBC1

BASL        EQU   $28
BASH        EQU   $29
P_ROW       EQU   $E0
P_COL       EQU   $E1
P_PTR       EQU   $E2          ;and $E3 (high byte)

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

*--------------------------------------
* Main: build the screen by calling
* PRINTAT eight times.
*--------------------------------------
START       JSR   HOME

* PRINTAT(0, 14, TITLE)
            LDA   #0
            STA   P_ROW
            LDA   #14
            STA   P_COL
            LDA   #<TITLE
            STA   P_PTR
            LDA   #>TITLE
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(2, 0, DIVIDER)
            LDA   #2
            STA   P_ROW
            LDA   #0
            STA   P_COL
            LDA   #<DIVIDER
            STA   P_PTR
            LDA   #>DIVIDER
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(4, 2, MENU_HDR)
            LDA   #4
            STA   P_ROW
            LDA   #2
            STA   P_COL
            LDA   #<MENU_HDR
            STA   P_PTR
            LDA   #>MENU_HDR
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(6, 4, OPT1)
            LDA   #6
            STA   P_ROW
            LDA   #4
            STA   P_COL
            LDA   #<OPT1
            STA   P_PTR
            LDA   #>OPT1
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(7, 4, OPT2)
            LDA   #7
            STA   P_ROW
            LDA   #4
            STA   P_COL
            LDA   #<OPT2
            STA   P_PTR
            LDA   #>OPT2
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(8, 4, OPT3)
            LDA   #8
            STA   P_ROW
            LDA   #4
            STA   P_COL
            LDA   #<OPT3
            STA   P_PTR
            LDA   #>OPT3
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(10, 0, DIVIDER)
            LDA   #10
            STA   P_ROW
            LDA   #0
            STA   P_COL
            LDA   #<DIVIDER
            STA   P_PTR
            LDA   #>DIVIDER
            STA   P_PTR+1
            JSR   PRINTAT

* PRINTAT(23, 13, FOOTER)
            LDA   #23
            STA   P_ROW
            LDA   #13
            STA   P_COL
            LDA   #<FOOTER
            STA   P_PTR
            LDA   #>FOOTER
            STA   P_PTR+1
            JSR   PRINTAT

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* PRINTAT subroutine
*
* Computes the address of (P_ROW, P_COL)
* via BASCALC + P_COL, then walks the
* null-terminated string at P_PTR,
* writing each character with the high
* bit forced on.
*--------------------------------------
PRINTAT     LDA   P_ROW
            JSR   BASCALC          ;BASL,BASH = row base
            LDA   BASL
            CLC
            ADC   P_COL
            STA   BASL              ;BASL += P_COL
            BCC   :NOC
            INC   BASH               ;carry into BASH if needed
:NOC        LDY   #0
:LOOP       LDA   (P_PTR),Y
            BEQ   :DONE
            ORA   #$80
            STA   (BASL),Y
            INY
            BNE   :LOOP
:DONE       RTS

*--------------------------------------
* String data
*--------------------------------------
TITLE       ASC   "PRINTAT DEMO"
            DFB   $00
DIVIDER     ASC   "----------------------------------------"
            DFB   $00
MENU_HDR    ASC   "MENU:"
            DFB   $00
OPT1        ASC   "1. PLAY GAME"
            DFB   $00
OPT2        ASC   "2. HIGH SCORES"
            DFB   $00
OPT3        ASC   "3. QUIT"
            DFB   $00
FOOTER      ASC   "PRESS ANY KEY"
            DFB   $00
