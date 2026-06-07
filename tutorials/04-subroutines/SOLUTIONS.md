# Stage 4 solutions

## 1. `PRINTHLINE(row, col, length, char)`

Two new zero-page bytes and a tweaked loop:

```
P_LEN       EQU   $E4
P_CHAR      EQU   $E5

PRINTHLINE  LDA   P_ROW
            JSR   BASCALC
            LDA   BASL
            CLC
            ADC   P_COL
            STA   BASL
            BCC   :NOC
            INC   BASH
:NOC        LDA   P_CHAR
            ORA   #$80
            LDY   #0
            LDX   P_LEN
:LOOP       STA   (BASL),Y
            INY
            DEX
            BNE   :LOOP
            RTS
```

Notice this uses *two* registers as counters: Y advances the screen
position while X counts down the remaining length. We could have
used a single counter but it requires either `CPY #P_LEN` (Y is the
column, P_LEN the count) per iteration or `LDA P_LEN : CMP Y`. Two
counters is cheaper.

Caller pattern:

```
            LDA   #5
            STA   P_ROW
            LDA   #10
            STA   P_COL
            LDA   #20
            STA   P_LEN
            LDA   #'='
            STA   P_CHAR
            JSR   PRINTHLINE
```

## 2. `CLRLINE(row)`

Once `PRINTHLINE` exists, `CLRLINE` is one delegation:

```
CLRLINE     LDA   #0
            STA   P_COL
            LDA   #40
            STA   P_LEN
            LDA   #' '
            STA   P_CHAR
            JMP   PRINTHLINE   ;tail call: PRINTHLINE's RTS returns to OUR caller
```

`JMP PRINTHLINE` instead of `JSR PRINTHLINE : RTS` saves 7 cycles
and 2 bytes. It works because `PRINTHLINE`'s `RTS` pops the
*caller's* return address — there's no `JSR` for it to undo.

That's the 6502 tail-call optimization, done by hand. Useful when a
subroutine ends by calling another and you don't need to do
anything after.

## 3. Call depth tracker

```
CALL_DEPTH  EQU   $E6
MAX_DEPTH   EQU   $E7

* In your init code:
            LDA   #0
            STA   CALL_DEPTH
            STA   MAX_DEPTH

* PRINTAT prologue:
PRINTAT     INC   CALL_DEPTH
            LDA   CALL_DEPTH
            CMP   MAX_DEPTH
            BCC   :OLDMAX
            STA   MAX_DEPTH
:OLDMAX     ; ...rest of PRINTAT unchanged, plus DEC CALL_DEPTH before RTS
            ...
            DEC   CALL_DEPTH
            RTS
```

After the eight top-level `PRINTAT` calls in the main program,
`CALL_DEPTH` will be `0` (each call increments then decrements) and
`MAX_DEPTH` will be `1` (one level of nesting). To make it more
interesting, wrap:

```
PRINTAT_LOG INC   CALL_DEPTH
            ...           ;save MAX_DEPTH update
            JSR   PRINTAT
            DEC   CALL_DEPTH
            RTS
```

Now calling `PRINTAT_LOG` produces `MAX_DEPTH = 2` (because
`PRINTAT_LOG` is depth 1 *and* it calls `PRINTAT` which is depth
2).

This is a tiny stack profiler. Useful for checking that recursive
or mutually-recursive code stays within the 128-deep limit.

Print it at the end with a hex-print snippet:

```
* in: A = byte to print, BASL/BASH = screen address
PRINT_HEX   PHA
            LSR
            LSR
            LSR
            LSR
            JSR   PRINT_NIB
            PLA
            AND   #$0F
            ; fall through

PRINT_NIB   ORA   #$30          ;'0'..'9'
            CMP   #'9'+1
            BCC   :OUT
            ADC   #6             ;skip ':'..'@' for 'A'..'F'
:OUT        ORA   #$80
            STA   (BASL),Y
            INY
            RTS
```

(The `BCC : ADC #6` trick advances from `'9'+1` straight to `'A'`,
skipping the punctuation in between. Six bytes of code; classic
6502 idiom.)
