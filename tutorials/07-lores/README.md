# Stage 7 — Lo-res graphics

**Source:** `src/SHAPES.S`
**Build:** `make PROGRAM=SHAPES run`

The Apple II's "lo-res" graphics mode is a clever bit of hardware
sharing: the *same* `$0400-$07FF` memory you've been writing
characters to is reinterpreted as a 40-column x 48-row colored
pixel grid. The byte you wrote to display `'A'` shows up as a
colored block whose nibbles select two stacked colors.

That dual interpretation depends on which display mode the hardware
is in, and the hardware mode is selected by reading from a small
set of magic addresses called *soft switches*.

## What you'll learn

- What soft switches are and which ones control the video mode
- That lo-res and text share the *same* memory
- Why each byte is two stacked half-pixels with separate colors
- The 16-color palette
- The basic "set mode, draw, restore mode, exit" flow

## Soft switches

Reading or writing certain addresses in the `$C000-$C07F` range
has hardware side effects that have nothing to do with the byte
value. They're "switches" because each pair sets or clears a single
hardware flag.

The video-related soft switches are:

| Address | Effect of reading |
|---|---|
| `$C050` | Graphics mode on (TEXT off) |
| `$C051` | Text mode on |
| `$C052` | Full-screen graphics (MIXED off) |
| `$C053` | Mixed (top 20 rows graphics, bottom 4 rows text) |
| `$C054` | Display page 1 (`$0400-$07FF` for text/lo-res) |
| `$C055` | Display page 2 (`$0800-$0BFF`) |
| `$C056` | Lo-res (HIRES off) |
| `$C057` | Hi-res |

To get to lo-res, full-screen, page 1: `LDA $C050 : LDA $C052 :
LDA $C054 : LDA $C056`. The `LDA` value you get back is the
side-effect register's value, which is rarely useful — you're
doing it for the side effect.

There are non-video soft switches at higher addresses for the
80-column card, keyboard, joystick, etc. Same pattern. The "soft"
in the name distinguishes them from hardware DIP switches; they're
software-controlled state.

## Lo-res shares the text page

When you're in lo-res mode and you write `$33` to `$0400`, the
display shows two stacked pixels at column 0, rows 0-1: color 3
(purple) on top and color 3 below. The video circuit reads each
byte as "low nibble = color of top half-pixel, high nibble = color
of bottom half-pixel."

But the *memory* is the same. If you switch back to text mode
without clearing, that `$33` will display as character `$33` — the
ASCII digit `'3'`. (Run `SHAPES.S` and remove the `JSR HOME` from
the exit path to see this.)

### Resolution

A text row occupies 1 byte per column × 40 columns. In lo-res, that
becomes 2 stacked color pixels × 40 columns. The text page has 24
rows, so lo-res has 24 × 2 = **48 vertical pixels**.

That gives you a 40×48 display in pure graphics mode, or 40×40
graphics + 4 lines of text at the bottom in mixed mode (the bottom
4 text rows show text; the top 20 rows show graphics).

### Memory layout

Same `BASCALC`-style interleaved layout as text. Row R's base
address is identical to where text row R lives. To set lo-res cell
`(col, row)`, you compute the byte address (col, row/2) and modify
the appropriate nibble:

```
* set the top pixel of (col, row) to color X
LDA  (BASL),Y        ;Y = col, BASL = base of row/2
AND  #$F0
ORA  PIXEL_TOP_X     ;PIXEL_TOP_X = X in low nibble
STA  (BASL),Y
```

In `SHAPES.S` we sidestep this by always setting both nibbles to
the same color, so a `STA (BASL),Y` paints both stacked pixels in
one go.

## The 16 colors

The lo-res palette is fixed in hardware. Here's the standard table
(the names are conventional; exact hue depends on monitor):

| # | Color | # | Color |
|---|---|---|---|
| 0 | Black | 8 | Brown |
| 1 | Magenta | 9 | Orange |
| 2 | Dark blue | 10 | Grey (2) |
| 3 | Purple | 11 | Pink |
| 4 | Dark green | 12 | Green |
| 5 | Grey (1) | 13 | Yellow |
| 6 | Medium blue | 14 | Aqua |
| 7 | Light blue | 15 | White |

Colors 5 and 10 are both "grey" but generated from different NTSC
phase relationships; on a color TV they look identical, on a
monochrome screen they're the same shade.

The byte that paints two stacked pixels of color X is `X * 17` =
`(X<<4) | X` = `$X1X1` shifted into a byte: `$11`, `$22`, ...,
`$FF`. The palette table in `SHAPES.S` precomputes these.

## Walking through `SHAPES.S`

```
            LDA   TXTOFF
            LDA   MIXOFF
            LDA   PAGE1
            LDA   HIRESOFF
```

Four soft-switch reads to enter the mode. Order doesn't matter; the
flags are independent.

```
            LDA   #0
            STA   ROW
:CRL        LDA   ROW
            JSR   BASCALC
            LDA   #0
            LDY   #0
:CCL        STA   (BASL),Y
            INY
            CPY   #40
            BNE   :CCL
            INC   ROW
            LDA   ROW
            CMP   #24
            BNE   :CRL
```

Clear loop. Same shape as `FILL.S` from stage 2, but writing `$00`
(black) into every byte. **Important**: we have to clear the
graphics page ourselves. Switching to graphics mode doesn't
re-initialise memory — whatever was there from the previous text
display is now reinterpreted as colored pixels. (If you skipped the
clear and ProDOS happened to leave `$20`-ish bytes there, you'd see
a screenful of medium-blue-on-black.)

```
:PRL        LDA   ROW
            JSR   BASCALC
            LDY   #0
            LDX   #0
:PCL        LDA   PALETTE,X
            STA   (BASL),Y
            INY
            STA   (BASL),Y
            INY
            INX
            CPX   #16
            BNE   :PCL
```

For each text row R (= each pair of pixel rows): walk colors 0-15,
writing each color twice (one column each). Y goes from 0 to 31,
X goes from 0 to 15. Two `STA (BASL),Y` per color to produce 2-wide
strips so we use exactly 32 of the 40 columns; cols 32-39 stay
black.

```
            LDA   TXTON
            JSR   HOME
```

On exit, flip the TEXT bit back on (`$C051`) and clear the screen.
If we didn't `HOME`, the bytes we wrote as colors would now display
as characters — colorful junk that the user might find confusing.

## Mixed mode (briefly)

Read `$C053` instead of `$C052` and you get the mixed mode: the top
40×40 area shows lo-res graphics, and rows 20-23 of the text page
show as actual text (whatever ASCII bytes are there). This is great
for games — a status line and message area at the bottom, gameplay
at the top, all from the same memory.

The graphics area takes rows 0-19 of the text page (20 rows × 2
pixels = 40 pixel rows). The text area takes rows 20-23.

## Exercises

1. **Mixed mode with a status line.** Read `$C053` instead of
   `$C052`. Print `"PRESS A KEY TO QUIT"` on row 23 (which is now
   text, not graphics). Note that you have to write to row 23
   *before* switching modes, or use `BASCALC` and write directly
   regardless of mode (it works because the bytes look like text
   when scanned out as text and like pixels when scanned out as
   pixels).
2. **Use page 2 (`$0800-$0BFF`).** Build the palette on page 2
   while the screen still shows text (page 1), then flip with `LDA
   $C055`. Then back to page 1 with `$C054`. This is double
   buffering — invisible composition, then atomic swap.
3. **Draw a filled rectangle.** Write a `RECT(x, y, w, h, color)`
   subroutine that fills a rectangular area. Parameters in zero
   page like stage 4's `PRINTAT`. Hint: each "y row" is one text
   row, but a `y` parameter that means *pixel* rows would let you
   handle odd-height rectangles; for that you'd need to read the
   existing byte, mask, and merge — proper sub-byte editing.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 7

| Want to... | Use |
|---|---|
| Enter lo-res full-screen page 1 | `LDA $C050 : LDA $C052 : LDA $C054 : LDA $C056` |
| Enter mixed mode (4 text lines) | `LDA $C053` (instead of `$C052`) |
| Return to text | `LDA $C051` |
| Flip to page 2 | `LDA $C055` |
| Paint a 2-pixel-tall cell | `STA (BASL),Y` where A = `(color<<4)\|color` |
| Edit a single half-pixel | Read, AND with `$F0` or `$0F`, ORA, write back |
| Clear the lo-res screen | Same as text clear: zero every byte at row bases |

### Address ranges to remember

| Range | When | What |
|---|---|---|
| `$0400-$07FF` | Text page 1 / lo-res page 1 | text chars *or* colored pixels |
| `$0800-$0BFF` | Text page 2 / lo-res page 2 | second display page |
| `$C050-$C057` | Always | video soft switches |
| `$C000-$C00F` | Always | keyboard data |
| `$C010-$C01F` | Always | keyboard strobe and one-byte hardware flags |
