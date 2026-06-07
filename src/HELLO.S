*--------------------------------------
* HELLO.SYSTEM
*
* Auto-running ProDOS SYS file.  ProDOS
* loads the first SYS file it finds in
* the volume directory at $2000 and JMPs
* in -- with BASIC.SYSTEM removed from
* the disk, that file is this one.
*
* Prints a greeting via the monitor's
* COUT routine, then waits for a key and
* reboots via the Disk II ROM entry.
*
* Build target: ProDOS SYS, type $FF,
* aux $2000.
*--------------------------------------

            ORG   $2000
            TYP   $FF
            DSK   HELLO

KBD         EQU   $C000
KBDSTRB     EQU   $C010
COUT        EQU   $FDED
DISKIIBOOT  EQU   $C600

START       LDX   #0
:LOOP       LDA   MSG,X
            BEQ   :WAIT
            ORA   #$80
            JSR   COUT
            INX
            BNE   :LOOP

:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            JMP   DISKIIBOOT

MSG         ASC   "HELLO, APPLE IIE!"
            DFB   $0D
            ASC   "PRESS A KEY TO REBOOT."
            DFB   $0D,$00
