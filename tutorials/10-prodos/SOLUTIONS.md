# Stage 10 solutions

## 1. CREATE + WRITE + CLOSE

To create a fresh file you need a CREATE call with all of its
seven parameters spelled out:

```
CREATE_PARMS DFB   7
             DA    PATHNAME_NEW
             DFB   $C3            ;access: read+write+rename+destroy ($C3)
             DFB   $04            ;file type: TXT
             DA    $0000          ;aux type: 0
             DFB   $01            ;storage type: 1 (seedling, < 512 bytes)
             DA    DATE_NOW       ;creation date (you can leave 0,0)
             DA    TIME_NOW
```

Then OPEN, WRITE, CLOSE:

```
            JSR   MLI
            DFB   $C0            ;CREATE
            DA    CREATE_PARMS
            BCS   :BAD

            JSR   MLI
            DFB   $C8            ;OPEN
            DA    OPEN_PARMS_NEW
            BCS   :BAD
            LDA   OPEN_REFNUM_NEW
            STA   WRITE_REFNUM
            STA   CLOSE_REFNUM_NEW

            JSR   MLI
            DFB   $CB            ;WRITE
            DA    WRITE_PARMS

            JSR   MLI
            DFB   $CC            ;CLOSE
            DA    CLOSE_PARMS_NEW
:BAD        RTS

WRITE_PARMS DFB   4
WRITE_REFNUM DFB   0
            DA    OUT_MSG
            DA    OUT_MSG_LEN
            DA    0              ;actual (output)

OUT_MSG     ASC   "HELLO BACK FROM A2FUSE-PRODOS!"
            DFB   $0D
OUT_MSG_LEN EQU   *-OUT_MSG
```

The `*-OUT_MSG` idiom (Merlin32: `EQU` to current PC minus a label)
gives you the string's length at assembly time.

After `make run` (with this code as the program), the disk has
`OUTPUT.TXT`. Confirm with `a2fuse catalog dist/WORK.po`.

## 2. Hex dump

```
* After successful OPEN + READ of 64 bytes:
            LDA   #16             ;16 bytes per row
            STA   ROWLEFT
            LDX   #0
:DL         JSR   PRINT_HEX_BYTE   ;in: BUFFER,X -- use the print pattern
            LDA   #' '+$80
            JSR   COUT
            INX
            DEC   ROWLEFT
            BNE   :CONT_ROW
            LDA   #$8D            ;CR
            JSR   COUT
            LDA   #16
            STA   ROWLEFT
:CONT_ROW   CPX   #64
            BNE   :DL

PRINT_HEX_BYTE
            LDA   BUFFER,X
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

ROWLEFT     DFB   0
```

The result is a classic 4-row, 16-bytes-per-row hex view of the
first 64 bytes. Useful for debugging.

To dump more, do multiple READs until ProDOS reports `ACTUAL_LO=0`
(EOF). Each successive read picks up where the last one left off
because ProDOS tracks the file position internally.

## 3. File-not-found

Change the pathname to something missing:

```
PATHNAME    DFB   12
            ASC   "/WORK/NOPE.X"
```

Run. The `BCC :OPEN_OK` doesn't take; the error path runs. The
hex error code shown should be `$46` ("file not found").

Try other malformed paths:

- No leading `/`: error `$40` (invalid pathname).
- Length byte wrong: usually `$40` or `$44`.
- Pointing at the wrong volume name: `$45` (volume not found).

This is the easiest way to learn the error map — break things on
purpose and read what ProDOS sends back. Real Apple II software
typically has a `PRINT_ERROR` routine like the one in `LOAD.S` but
with a table of strings indexed by error code.
