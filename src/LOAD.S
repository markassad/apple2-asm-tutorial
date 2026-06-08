*--------------------------------------
* LOAD.S
*
* Tutorial stage 10.  Reads /WORK/HELLO.TXT
* off the disk via ProDOS MLI and prints
* its contents to the text screen.
*
* The MLI calling convention:
*   JSR $BF00
*   DFB  cmd_byte
*   DA   ptr_to_param_block
* Carry is set on return if there was an
* error; A holds the ProDOS error code.
*
* Before running this demo, drop a text
* file on the disk:
*   echo "HELLO FROM PRODOS" > /tmp/hello.txt
*   a2fuse put dist/WORK.po /tmp/hello.txt HELLO.TXT --type '$04'
*
* Build: make PROGRAM=LOAD run
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   LOAD

MLI         EQU   $BF00
HOME        EQU   $FC58
COUT        EQU   $FDED

KBD         EQU   $C000
KBDSTRB     EQU   $C010
DISKIIBOOT  EQU   $C600

START       JSR   HOME

* MLI: OPEN ($C8)
            JSR   MLI
            DFB   $C8
            DA    OPEN_PARMS
            BCC   :OPEN_OK
            JSR   PRINT_ERR
            JMP   :WAIT_KEY
:OPEN_OK
* Copy the refnum that OPEN wrote into the READ and CLOSE blocks
            LDA   OPEN_REFNUM
            STA   READ_REFNUM
            STA   CLOSE_REFNUM

* MLI: READ ($CA)
            JSR   MLI
            DFB   $CA
            DA    READ_PARMS
            BCC   :READ_OK
            JSR   PRINT_ERR
            JMP   :CLOSE
:READ_OK    JSR   PRINT_BUFFER

:CLOSE      JSR   MLI
            DFB   $CC
            DA    CLOSE_PARMS

:WAIT_KEY   LDA   KBD
            BPL   :WAIT_KEY
            STA   KBDSTRB
            JSR   HOME
            JMP   DISKIIBOOT

*--------------------------------------
* PRINT_BUFFER -- walk BUFFER for
* ACTUAL bytes, COUT each one.  Assumes
* ACTUAL_HI = 0 (file <= 255 bytes).
*--------------------------------------
PRINT_BUFFER
            LDX   #0
:PL         CPX   ACTUAL_LO
            BCS   :PD
            LDA   BUFFER,X
            ORA   #$80
            JSR   COUT
            INX
            BNE   :PL
:PD         RTS

*--------------------------------------
* PRINT_ERR -- print "ERR $XX " using
* the error code in A.  Trashes A, X.
*--------------------------------------
PRINT_ERR   PHA
            LDA   #'E'+$80
            JSR   COUT
            LDA   #'R'+$80
            JSR   COUT
            LDA   #'R'+$80
            JSR   COUT
            LDA   #' '+$80
            JSR   COUT
            LDA   #'$'+$80
            JSR   COUT
            PLA
            PHA
            LSR
            LSR
            LSR
            LSR
            JSR   :NIB
            PLA
            AND   #$0F
:NIB        ORA   #$30
            CMP   #$3A
            BCC   :OUT
            CLC
            ADC   #6
:OUT        ORA   #$80
            JSR   COUT
            RTS

*--------------------------------------
* MLI parameter blocks
*--------------------------------------
OPEN_PARMS  DFB   3              ;param count
            DA    PATHNAME       ;pointer to pathname
            DA    IOBUF          ;1024-byte buffer for ProDOS scratch
OPEN_REFNUM DFB   $00            ;output: file reference number

READ_PARMS  DFB   4              ;param count
READ_REFNUM DFB   $00            ;will be set from OPEN_REFNUM
            DA    BUFFER         ;destination buffer
            DA    256            ;request count (low/high)
ACTUAL_LO   DFB   $00
ACTUAL_HI   DFB   $00

CLOSE_PARMS DFB   1              ;param count
CLOSE_REFNUM DFB  $00            ;will be set from OPEN_REFNUM

* Pathname: length-prefixed ASCII, absolute path
PATHNAME    DFB   15
            ASC   "/WORK/HELLO.TXT"

* ProDOS scratch.  Must be 1024 bytes, page-aligned.  This block
* gets used by the MLI for tracking the open file.
            DS    \             ;align to next page boundary
IOBUF       DS    1024

* Data buffer: where the file content lands.
BUFFER      DS    256
