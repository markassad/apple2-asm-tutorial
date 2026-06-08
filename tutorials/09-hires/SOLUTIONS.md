# Stage 9 solutions

## 1. Bands at top and bottom

Replace the fill loop with two table-driven row paints:

```
* (Replace the :FILL loop with this block.)
            LDX   #0
:BANDL      LDA   ROW_LO,X
            STA   PTR
            LDA   ROW_HI,X
            STA   PTR+1
            LDY   #0
            LDA   #$7F
:BIL        STA   (PTR),Y
            INY
            CPY   #40
            BNE   :BIL
            INX
            CPX   #16             ;8 top + 8 bottom = 16 rows
            BNE   :BANDL

* Rows 0..7 (top band) and 184..191 (bottom band).
ROW_LO      DFB   $00,$00,$00,$00,$00,$00,$00,$00
            DFB   $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
ROW_HI      DFB   $40,$44,$48,$4C,$50,$54,$58,$5C
            DFB   $43,$47,$4B,$4F,$53,$57,$5B,$5F
```

Verify against the formula:

- Row 0: `$4000 + 0 + 0 + 0 = $4000` → LO `$00`, HI `$40` ✓
- Row 7: `$4000 + 7*$400 + 0 + 0 = $5C00` → LO `$00`, HI `$5C` ✓
- Row 184: `$4000 + 0 + 7*$80 + 2*$28 = $4000 + $380 + $50 =
  $43D0` → LO `$D0`, HI `$43` ✓
- Row 191: `$4000 + 7*$400 + 7*$80 + 2*$28 = $5FD0` → LO `$D0`,
  HI `$5F` ✓

You'll see a thin (8-pixel = 4-pixel-row-pair, since hi-res is
not stacked-pixel like lo-res) white bar at top and another at
bottom. The middle 176 rows stay black (or whatever was left in
hi-res page 2 from boot — running `make distclean install` gives
you a guaranteed-cleared start).

## 2. Plot a single pixel

```
* Inputs in zero page:
*   PX_LO  (low byte of X coord, 0..255)
*   PX_HI  (high byte of X coord, 0 or 1; this version assumes 0)
*   PY     (Y coord 0..191)
* Trashes A, X, Y, PTR, T1, T2.

T1          EQU   $24
T2          EQU   $25
PX_LO       EQU   $26
PY          EQU   $27

PLOT_XY     LDA   PY
            JSR   HBASE          ;PTR = base(Y)

            LDA   PX_LO
            STA   T1
            LDA   #0
            STA   T2
:DIVLOOP    LDA   T1
            CMP   #7
            BCC   :DIVDONE
            SEC
            SBC   #7
            STA   T1
            INC   T2
            JMP   :DIVLOOP
:DIVDONE    ; T2 = byte offset, T1 = bit within byte

            LDA   #1
            LDX   T1
            BEQ   :SHIFTDONE
:SHIFT      ASL                  ;A <<= 1
            DEX
            BNE   :SHIFT
:SHIFTDONE  STA   T1              ;T1 = bit mask

            LDY   T2
            LDA   (PTR),Y
            ORA   T1
            STA   (PTR),Y
            RTS

* HBASE: A = Y, returns PTR = base(Y).
HBASE       PHA
            AND   #$07            ;Y & 7
            STA   T1
            LDA   #0
            STA   T2
            LDX   T1
            BEQ   :S400DONE
:S400LOOP   CLC                   ;multiply T2:?? by $400 via 10 shifts
            ; ...full version is ~20 lines; in production use a 192-entry
            ;    table for Y → base, similar to ROW_LO/ROW_HI above
:S400DONE   ; ...
            RTS
```

The honest answer for production: don't compute. Precompute a
384-byte table (`HBASE_LO`, `HBASE_HI`, each 192 bytes) and look
up. That's stage 11's whole point.

## 3. Color stripes

The stripe demo: 4 different patterns, 24 rows each, repeated
twice for 192 rows.

Compute base addresses for 96 rows (24 × 4 stripes; you can
sidestep computing the rest because of the repetition). Or use the
formula at runtime.

The cleanest way: a 192-entry Y→base table plus a 96-entry
"pattern index" mapping Y mod 96 → which pattern.

```
* For each Y in 0..191:
*   pattern_index = (Y / 24) mod 4
*   pattern = PATTERN_TBL[pattern_index]
*   base = HBASE_LO[Y]/HBASE_HI[Y]
*   fill bytes base..base+39 with pattern

PATTERN_TBL  DFB  $2A,$55,$D5,$AA   ;green, violet, orange, blue
HBASE_LO     DFB  ...192 bytes...
HBASE_HI     DFB  ...192 bytes...
```

You can generate the 384 bytes of `HBASE_*` tables with a tiny
Python script:

```python
print("HBASE_LO    DFB", ",".join(
    f"${(0x4000 + (y&7)*0x400 + ((y>>3)&7)*0x80 + (y>>6)*0x28) & 0xff:02X}"
    for y in range(192)))
print("HBASE_HI    DFB", ",".join(
    f"${((0x4000 + (y&7)*0x400 + ((y>>3)&7)*0x80 + (y>>6)*0x28) >> 8) & 0xff:02X}"
    for y in range(192)))
```

Paste the output into your `.S` file.

The visual result is four horizontal bars of color (green,
violet, orange, blue, repeated). Apple II programmers built whole
games this way — most "color" hi-res tricks are clever
combinations of these few byte patterns.
