# Stage 7 solutions

## 1. Mixed mode with a status line

Two changes: read `$C053` instead of `$C052`, and print a status
message on row 23.

```
* In init, after HOME but before the soft switch reads:
            LDA   #23
            JSR   BASCALC
            LDY   #10
            LDX   #0
:SL         LDA   STATUS,X
            BEQ   :SD
            ORA   #$80
            STA   (BASL),Y
            INY
            INX
            BNE   :SL
:SD

* Then enter mixed mode (note $C053 instead of $C052):
            LDA   TXTOFF
            LDA   $C053          ;mixed: top 40 rows graphics, bottom 4 text
            LDA   PAGE1
            LDA   HIRESOFF

* ...rest of palette code unchanged...

STATUS      ASC   "PRESS A KEY"
            DFB   $00
```

The clear loop should now stop at row 19 (not 23) — rows 20-23
are the text area and you don't want to paint black "pixels" over
your status text.

```
* In :CRL loop:
            LDA   ROW
            CMP   #20            ;was #24
            BNE   :CRL
```

The palette loop should also stop at row 19.

## 2. Page 2 double buffering

Page 2 lives at `$0800-$0BFF`. `BASCALC` doesn't know about page 2
— it always returns page 1 addresses. Two options:

**Option A: write your own `BASCALC2`** that produces page-2
addresses. The formula is identical except `$0800` is the base
instead of `$0400`. Or just call `BASCALC` and `INC BASH` after, so
`BASL`/`BASH` points one page higher (page 2).

**Option B: use the alternate-byte trick** — write a routine that
takes a page-1 row, calls BASCALC, then adds `$04` to BASH.

Code:

```
* Like BASCALC, but for page 2.
BASCALC2    JSR   BASCALC
            INC   BASH
            INC   BASH
            INC   BASH
            INC   BASH
            RTS                 ;BASH += $04, moving from $04xx -> $08xx
```

Or set BASH directly to the page-2 high byte after BASCALC.

Then in your palette-paint loop call `BASCALC2` instead of
`BASCALC`. The screen will not visually update because you're still
displaying page 1. Once you've finished painting:

```
            LDA   $C055           ;flip display to page 2
```

Page 2 instantly shows. The transition is one frame; no flicker.

To flip back, `LDA $C054`.

This is what real games do for sprite animation: draw the next
frame on the hidden page, swap, repeat.

## 3. RECT subroutine

```
R_X         EQU   $E1            ;left
R_Y         EQU   $E2            ;top (in pixel rows; we'll truncate to text rows)
R_W         EQU   $E3            ;width in cols
R_H         EQU   $E4            ;height in pixel rows
R_COLOR     EQU   $E5            ;color 0-15

* Builds (color<<4)|color in A as a side effect.
RECT_FILL   LDA   R_COLOR
            STA   :TMPC
            ASL
            ASL
            ASL
            ASL
            ORA   :TMPC
            STA   :BYTE          ;byte to paint
            ; For each pixel row from R_Y to R_Y+R_H-1, paint the row
            LDA   R_Y
            STA   :PY
:RL         LDA   :PY
            LSR                   ;text row = pixel row / 2
            JSR   BASCALC
            LDY   R_X
            LDX   R_W
            LDA   :BYTE
:CL         STA   (BASL),Y
            INY
            DEX
            BNE   :CL
            INC   :PY
            LDA   :PY
            SEC
            SBC   R_Y
            CMP   R_H
            BCC   :RL
            RTS

:TMPC       DFB   0
:BYTE       DFB   0
:PY         DFB   0
```

This version always paints both pixels in a row (because we paint
the whole text-row byte). For true pixel-precise rectangles, you'd
need to:

- Detect whether the current pixel row is an *even* (top half) or
  *odd* (bottom half) pixel row.
- For even: read byte, AND `#$F0` (clear low nibble), OR the color,
  write.
- For odd: read byte, AND `#$0F`, OR `color<<4`, write.

That's roughly twice the code; left as a tougher exercise.
