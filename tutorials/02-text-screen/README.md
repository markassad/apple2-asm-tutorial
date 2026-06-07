# Stage 2 — The text screen

**Source:** `src/FILL.S`
**Build:** `make PROGRAM=FILL run`

In stage 1 we used `COUT` to print one character at a time. `COUT`
hides a lot of work from you: it figures out where the cursor is,
computes the right memory address, handles scroll, advances the
cursor. This stage skips `COUT` entirely and writes characters
directly into screen memory. That means understanding where screen
memory *is*, and what's weird about it.

## What you'll learn

- Where the text page lives in memory (`$0400-$07FF`)
- Why row N+1 doesn't follow row N in memory — the "interleaved" layout
- "Screen holes" — bytes in the text page that don't show up on screen
  but the hardware uses for slot-card scratch
- The `BASCALC` ROM routine that translates a row number to the
  address of column 0 of that row
- Indirect-indexed addressing `(zp),Y` — the workhorse for writing
  into anything bigger than 256 bytes

## The 40x24 text page lives at $0400-$07FF

That's 1024 bytes. The math: 40 columns × 24 rows × 1 byte/char =
960 bytes. There are 64 unused bytes. Hold that fact.

If the layout were *linear*, row 0 would be `$0400-$0427`, row 1
would be `$0428-$044F`, and so on. The 6502 was built in an era when
making row arithmetic cheap mattered more than making it obvious to
the programmer — and the Apple II's hardware engineer (Wozniak)
made a layout that the *6502's indexed addressing modes* like, not
one *humans* like.

Here's the real layout:

| Row | Address  | Row | Address  | Row | Address  |
|-----|----------|-----|----------|-----|----------|
|  0  | `$0400`  |  8  | `$0428`  | 16  | `$0450`  |
|  1  | `$0480`  |  9  | `$04A8`  | 17  | `$04D0`  |
|  2  | `$0500`  | 10  | `$0528`  | 18  | `$0550`  |
|  3  | `$0580`  | 11  | `$05A8`  | 19  | `$05D0`  |
|  4  | `$0600`  | 12  | `$0628`  | 20  | `$0650`  |
|  5  | `$0680`  | 13  | `$06A8`  | 21  | `$06D0`  |
|  6  | `$0700`  | 14  | `$0728`  | 22  | `$0750`  |
|  7  | `$0780`  | 15  | `$07A8`  | 23  | `$07D0`  |

Notice the three columns: rows 0-7 start at `$04n0`/`$05n0`/`$06n0`/
`$07n0` with `n=0,8`. Rows 8-15 add `$28` to each base. Rows 16-23 add
another `$28` (or `$50` from the rows-0-7 set).

The formula: `base(row) = $400 + (row mod 8) * $80 + (row div 8) * $28`.

You could write that by hand each frame, but you'd be wasting cycles
recomputing what every Apple II program before yours also needed.
The ROM routine `BASCALC` ($FBC1) does it for you: pass the row in
the accumulator, get `BASL`/`BASH` (`$28`/`$29` in zero page) set to
the row's base address.

### Why this layout?

The TV scan path on a 6502-class machine is what drove this. The
Apple II's video circuitry, while drawing the screen top-to-bottom,
reads bytes from memory and pretends they're pixels. With the
interleaved layout, the hardware can use simple adders on the
program counter equivalent (a counter chain) to fetch consecutive
scanlines without doing actual division. Wozniak traded a bit of CPU
math (the `BASCALC` calculation) for a lot fewer hardware gates.

You don't need to memorize the layout — `BASCALC` makes it
irrelevant for normal use. But if you ever stare at a hex dump of
`$0400-$07FF` looking for a string you wrote and it's not where you
expected, you'll know why.

## Screen holes

960 bytes are visible. 64 are not. Those 64 *exist* in the address
range `$0400-$07FF`, but the video hardware skips them. They are:

`$0478-$047F`, `$04F8-$04FF`, `$0578-$057F`, `$05F8-$05FF`,
`$0678-$067F`, `$06F8-$06FF`, `$0778-$077F`, `$07F8-$07FF`

That's 8 bytes near the end of every `$80`-aligned page in
`$0400-$07FF`.

Apple reserved these "screen holes" for slot-card peripherals. Slot
1's card can scratch in `$0478,$04F8,$0578,$05F8,$0678,$06F8,$0778,
$07F8` (one byte per page). Slot 2 gets the next byte (`$0479`...).
Disk II in slot 6 stores its status in the slot-6 holes during disk
I/O.

If you write to a screen hole from your code, the byte sits in
memory but never appears on screen. Useful: you can stash 64 bytes
of state inside the text page where it won't disrupt the display.
Dangerous: if you happen to also touch the disk during that time,
the disk driver will overwrite your bytes without warning.

## The source

```
:ROWLOOP    LDA   ROW
            CLC
            ADC   #'A'         ;char for this row = 'A' + row index
            ORA   #$80         ;force normal display attribute
            STA   CHAR
            LDA   ROW
            JSR   BASCALC      ;sets BASL,BASH to row base
            LDA   CHAR
            LDY   #0
:COLLOOP    STA   (BASL),Y     ;write char into (row, col)
            INY
            CPY   #40
            BNE   :COLLOOP
            INC   ROW
            LDA   ROW
            CMP   #24
            BNE   :ROWLOOP
```

The outer loop walks rows 0-23. The inner loop walks columns 0-39.

`LDA ROW : CLC : ADC #'A'` computes the character: `'A'` is `$41`,
plus the row number. Row 0 → `$41` (`'A'`). Row 1 → `$42` (`'B'`).
Row 23 → `$58` (`'X'`).

We stash the char in zero-page byte `CHAR` because we're about to
clobber the accumulator twice: first by reloading `ROW` for
`BASCALC`, then by `BASCALC` itself (which uses A as input and
doesn't promise to preserve it).

`BASCALC` is one of those ROM routines where you should pretend the
accumulator and X register are gone afterward. The Y register
survives. `BASL` and `BASH` (at `$28`/`$29`) hold the row's base
address.

Then `LDA CHAR : LDY #0 : STA (BASL),Y` is the actual write.
**`STA (BASL),Y` is indirect-indexed addressing.** The CPU reads the
two bytes at `$28`/`$29` to get a 16-bit base address, adds Y, and
stores A there. So with `BASL`/`BASH` pointing at row 5's base
(`$680`) and `Y=37`, the byte lands at `$06A5`.

`INY : CPY #40 : BNE :COLLOOP` fills columns 0-39. `INC ROW : LDA ROW
: CMP #24 : BNE :ROWLOOP` advances to the next row until we've done
all 24.

When the loop ends, we wait for a key (same idiom as stage 1),
clear the screen with `HOME`, and reboot.

## What the result looks like

Twenty-four rows of repeated letters: `AAAAAA...` on row 0,
`BBBBBB...` on row 1, all the way to `XXXXXX...` on row 23.
Visually it looks like a perfectly ordinary grid. The whole point of
this exercise is that the layout you *see* hides a memory layout
that's wildly non-sequential.

If you set a watchpoint on `$0480` in the MAME debugger (`F4` to
enter, `wpset 480,1,w` or `watch -addr 0x480` depending on version),
you'd see the watchpoint fire 40 times in a row — once per
`STA (BASL),Y` in the row-1 pass. The watchpoint on `$0428` would
fire 40 times in the row-8 pass. The bytes for "row 1" aren't next to
the bytes for "row 0" in memory at all; they're a full `$80` apart.

## Exercises

1. **Draw a border.** Modify `FILL.S` so only rows 0, 23, column 0,
   and column 39 are filled — leave the interior blank. The border
   should be filled with `*` characters. Hint: you'll need two extra
   loops, one for the top/bottom rows and one for the left/right
   columns of the middle rows.
2. **Show the row numbers.** Print "ROW 00" through "ROW 23" in the
   first six columns of each row, with the rest of the row blank.
   You'll need to convert a row number (0-23) to two ASCII digits.
   Hint: divide-by-10 by repeated subtraction works fine here.
3. **Write to a screen hole.** Add a `LDA #'X'+$80 : STA $0478` near
   the end of the program (before the `WAIT` loop). Run it. Where
   does the `X` show up? What does this tell you about the screen
   hole bytes? Now try `STA $0478` *and* `STA $0479` — does anything
   change?

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 2

| Want to... | Use |
|---|---|
| Get the base address of text row N | `LDA #N : JSR $FBC1` (`BASCALC`) |
| Write at (col, row) after `BASCALC` | `LDY col : STA (BASL),Y` |
| Reset the cursor and clear | `JSR $FC58` (`HOME`) |
| Read a row's base directly | Bytes at zero page `$28`/`$29` after `BASCALC` |

### The "real" memory map of the text page (visual)

```
$0400        $0428        $0450        $0478
  |            |            |            |
  v            v            v            v
[row 0    ][row 8    ][row 16   ][hole 1.1]
[row 1    ][row 9    ][row 17   ][hole 1.2]
[row 2    ][row 10   ][row 18   ][hole 1.3]
[row 3    ][row 11   ][row 19   ][hole 1.4]
[row 4    ][row 12   ][row 20   ][hole 1.5]
[row 5    ][row 13   ][row 21   ][hole 1.6]
[row 6    ][row 14   ][row 22   ][hole 1.7]
[row 7    ][row 15   ][row 23   ][hole 1.8]

(this is just the $0400-$047F page; same pattern repeats
across $0500, $0600, $0700)
```

The "hole" column at right is the 8 bytes per `$80` page that the
video hardware skips. Slot N's card uses byte N within each hole.
