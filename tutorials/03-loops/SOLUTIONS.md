# Stage 3 solutions

## 1. 6x6 table

Change the outer loop bounds and update the title and Y math.

```
* outer loop tests
            CMP   #7              ;was #9
            ...
            CMP   #7              ;was #9
```

Title becomes `"MULTIPLICATION TABLE 1-6"` (24 chars again — same
centering at column 8). Each cell is still 3 chars; six cells fit
in 18 columns plus the 2-char `R:` label leaves room to recenter
the row by starting at a different `Y` base.

For a 6x6 you might also widen each cell to 4 chars (max product is
36, but 6\*6=36 fits in 2 digits so 3 chars is fine). If you want
prettier spacing:

```
            LDA   COL
            ASL                  ;*2
            ASL                  ;*4 (cell width = 4)
            CLC
            ADC   #2             ;start column
            TAY
```

Now the cells are 4 wide and start at column 2.

## 2. Powers of 2

Replace the product computation with a doubling loop. Stay within a
byte by stopping at `2^7 = 128`. The print code already handles
1-99 (we have `TENS` and `ONES`); add 3-digit support by adding a
`HUNDREDS` divide.

```
* Compute 2^(COL-1) into A.
            LDA   #1
            LDX   COL
            DEX                  ;COL-1 doublings
            BEQ   :POWDONE
:POWLOOP    ASL
            DEX
            BNE   :POWLOOP
:POWDONE    STA   PROD

* Divide by 100 first, then by 10
            LDX   #0
:HLOOP      CMP   #100
            BCC   :HDONE
            SEC
            SBC   #100
            INX
            JMP   :HLOOP
:HDONE      STX   HUNDREDS
            ; now A is < 100; do tens and ones as before
            ...
```

You'll need to add a `HUNDREDS` zp byte and a print position for
the hundreds digit (cell becomes 4 chars wide to fit 3 digits + a
leading space).

If you want to keep the 16-bit case (2^8 = 256 and beyond), you
need a 16-bit product (two zero page bytes, low and high), and the
`ASL` becomes `ASL low : ROL high`. Out of scope here but classic
6502 16-bit arithmetic.

## 3. Inverse diagonal

The test is `if ROW == COL`. In 6502 terms:

```
            LDA   ROW
            CMP   COL
            BNE   :NORMAL
            ; diagonal: use plain ASCII (no ORA #$80) so bits 7-6 = 00 = inverse
            LDA   ONES
            CLC
            ADC   #'0'
            STA   (BASL),Y       ;no ORA #$80
            JMP   :DIAGSKIP
:NORMAL     LDA   ONES
            CLC
            ADC   #'0'
            ORA   #$80
            STA   (BASL),Y
:DIAGSKIP
```

A nicer factoring: compute a "use inverse?" flag once per cell and
conditionally `ORA #$80` or not. The simplest implementation is the
above branch.

In the original code we set bit 7 with `ORA #$80` to force *normal*
display. Inverse display is bits 7-6 = `00`, so we leave the bits
clear. For the `' '` padding and the `':'` label you may want to
leave those normal even on diagonal cells; the test only matters
where digits go.
