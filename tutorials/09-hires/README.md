# Stage 9 — Hi-res graphics fundamentals

**Source:** `src/HIRES.S`
**Build:** `make PROGRAM=HIRES run`

Lo-res gave you a 40x48 grid of fat colored squares. Hi-res gives
you 280x192 monochrome-with-color-fringing — the iconic Apple II
look. You pay for the higher resolution in two ways: the memory
layout is profoundly annoying, and the color story is intricate.

The demo here is the simplest thing that *visibly* proves the
mode switch and memory writes work: clear hi-res page 2 to white
and wait for a key. The interesting content is in the prose —
once you understand the formula and the soft switches, drawing
arbitrary shapes is exercise work.

## What you'll learn

- Where the two hi-res pages live and why we use page 2 from a SYS
  file
- The 280x192 resolution and the 7-pixels-per-byte truth
- What hi-res "color" actually is (NTSC artifacting, briefly)
- The Y-to-address formula and where its three terms come from
- Why the Applesoft ROM hi-res routines are a trap from a SYS file
- The minimal sequence of soft switches to land in hi-res page 2

## Two hi-res pages: $2000 and $4000

Hi-res page 1: `$2000-$3FFF` (8 KB).
Hi-res page 2: `$4000-$5FFF` (8 KB).

Page 1 is the default, the one Applesoft `HGR` initialises. But —
notice — `$2000` is *also* where ProDOS loads SYS files. **Your
program is sitting on top of hi-res page 1.** Switching to hi-res
page 1 displays your own code as colored pixels, and the moment
you clear page 1 you wipe out your own executing code
mid-instruction.

The standard workaround for SYS files is to use *page 2*
(`$4000-$5FFF`) instead. Your code stays at `$2000` and the
display reads pixels from `$4000`. This stage does that.

If you must use page 1, the move is:

1. At startup, immediately copy your own code from `$2000` upward
   to some safe address (say `$6000`).
2. `JMP $6000` to the relocated copy.
3. Now you can use `$2000-$3FFF` as a frame buffer.

For the tutorial, page 2 is much less work.

## The mode switch (without Applesoft)

The "right" way to enter hi-res from Applesoft is `JSR $F3D8`
(`HGR2`). That routine reads four soft switches, clears page 2,
and resets a half-dozen Applesoft zero-page variables tied to
plot state. It works fine from BASIC.

It does *not* work reliably from a bare ProDOS SYS file like
ours. BASIC.SYSTEM isn't running, the Applesoft init has never
fired, and the ROM expects state in zero page (`$1C`, `$26`, `$30`,
`$E0`-`$E7`) that hasn't been populated. Calling `HGR2` from cold
ProDOS context lands you in a partial setup with display
artifacts.

The reliable replacement is four `LDA`s on the soft switches we
actually care about:

```
            LDA   $C050         ;TEXT off (graphics on)
            LDA   $C052         ;MIXED off (full screen)
            LDA   $C055         ;PAGE 2
            LDA   $C057         ;HIRES on
```

That's it. After those four reads the display is hi-res page 2.

The reads' return values are garbage — they're side effects. The
side effects are independent, so the order doesn't matter (in
practice; you'll see various canonical orderings).

To get back to text: `LDA $C051 : JSR $FC58`. The latter is
`HOME`, which clears the text screen.

## The byte and bit encoding

Each byte of hi-res memory encodes 7 horizontal pixels:

```
bit 7    bit 6  bit 5  bit 4  bit 3  bit 2  bit 1  bit 0
[color]  [px6]  [px5]  [px4]  [px3]  [px2]  [px1]  [px0]
```

Bits 0-6 are the 7 pixels left-to-right. Bit 7 is the **color
phase flag** — it doesn't *display* anything; it shifts how the
NTSC decoder colors the alternating-bit patterns.

Memorise the canonical values:

| Byte | Meaning |
|---|---|
| `$00` | All pixels off (black) |
| `$7F` | All pixels on, color phase 0 → white-ish (green-violet fringing) |
| `$FF` | All pixels on, color phase 1 → white-ish (orange-blue fringing) |
| `$2A` (= `0010 1010`) | Alternating, phase 0 → green |
| `$55` (= `0101 0101`) | Alternating, phase 0 → violet |
| `$AA` (= `1010 1010`) | Alternating, phase 1 → blue |
| `$D5` (= `1101 0101`) | Alternating, phase 1 → orange |

The demo writes `$7F` everywhere, so the screen is uniformly
white(-ish). On a color CRT you'd see slight green and violet
fringing at the very edges; on a modern emulator's RGB display
it looks cleanly white.

## The Y-to-address formula

```
base(Y) = $4000 + (Y & 7) * $400
                + ((Y >> 3) & 7) * $80
                + (Y >> 6) * $28
```

Three terms:

- `(Y & 7) * $400` — selects one of 8 "scanline groups" within an
  8-row band. Spacing is `$400` (1 KB).
- `((Y >> 3) & 7) * $80` — selects one of 8 rows within a "third"
  of the screen. Spacing is `$80` (128 bytes).
- `(Y >> 6) * $28` — selects one of 3 thirds (top, middle, bottom).
  Spacing is `$28` (40 bytes, the same row stride as text).

The interleaving is even more aggressive than the text page's
because there are 192 rows to fit into 8 KB, not 24 into 1 KB.

Some specific values to anchor your intuition:

| Y | Calc | base |
|---|---|---|
| 0 | $4000 | `$4000` |
| 1 | $4000 + $400 | `$4400` |
| 7 | $4000 + 7*$400 | `$5C00` |
| 8 | $4000 + 0 + $80 | `$4080` |
| 64 | $4000 + 0 + 0 + $28 | `$4028` |
| 128 | $4000 + 0 + 0 + $50 | `$4050` |
| 191 | $4000 + $1C00 + $380 + $50 | `$5FD0` |

Within a row, the byte at offset `X / 7` of `base(Y)` contains
the pixel at column X. The bit within that byte is `X mod 7`. For
column 0, that's bit 0 of byte 0. For column 139 (middle), that's
bit 6 of byte 19. For column 279 (right edge), that's bit 6 of
byte 39.

So plotting a single pixel at (X, Y) is six steps:

1. Compute `base(Y)`.
2. `offset = X / 7`.
3. `bit = X mod 7`.
4. Read byte at `base(Y) + offset`.
5. OR in `1 << bit`.
6. Write back.

The Apple II has no `MUL` or `DIV`, so the `X / 7` and `X mod 7`
take a table or a small `SBC #7` loop. This is the kind of
inner-loop math that makes hi-res code feel heavy. The
optimization story is: precompute Y → base tables, and (X → byte
offset, bit mask) tables. Stage 11's optimization tricks are
written in part because of how often you'd need them here.

## The demo walkthrough

```
            LDA   TXTOFF
            LDA   MIXOFF
            LDA   PAGE2
            LDA   HIRESON
```

Four soft-switch reads to land in hi-res page 2. The display is
now reading bytes from `$4000-$5FFF` (whatever happens to be
there).

```
            LDA   #$00
            STA   PTR
            LDA   #$40
            STA   PTR+1
            LDX   #$20
            LDY   #$00
            LDA   #$7F
:FILL       STA   (PTR),Y
            INY
            BNE   :FILL
            INC   PTR+1
            DEX
            BNE   :FILL
```

`PTR`/`PTR+1` is a 16-bit pointer in zero page that walks
$4000 → $4FFF → $5FFF. The outer loop counter `X` counts down 32
pages (= 8 KB). The inner loop writes `$7F` to all 256 bytes of
the current page using Y as the offset.

When Y wraps from `$FF` back to `$00`, we INC `PTR+1` to point
at the next page, DEX, and continue. When X hits 0 we've covered
the whole page.

Total: 8192 stores, each ~6 cycles plus loop overhead =~ 50,000
cycles =~ 50 ms. You see it as instantaneous.

The screen now shows uniform white.

```
:WAIT       LDA   KBD
            BPL   :WAIT
            STA   KBDSTRB
            LDA   TXTON
            JSR   HOME
            JMP   DISKIIBOOT
```

Standard exit: wait for key, flip TEXT back on, clear, reboot.

## Exercises

1. **A solid white *band*.** Modify the fill loop to only write
   `$7F` to a small number of contiguous rows — say rows 0-7 (top
   band) and rows 184-191 (bottom band). You need a table of 16
   base addresses (8 for each band) plus a per-row 40-byte fill.
   Top band: `$4000, $4400, $4800, $4C00, $5000, $5400, $5800,
   $5C00`. Bottom band: `$43D0, $47D0, $4BD0, $4FD0, $53D0,
   $57D0, $5BD0, $5FD0`. Verify against the formula above.
2. **Plot a single pixel.** Write `PLOT_XY(x, y)` that takes
   coordinates and sets one pixel. Use the formula. You'll
   need a 7-divide somewhere — repeated `SBC #7` works for
   a tutorial.
3. **Color stripes.** Fill rows 0-23 with `$2A` (green), rows
   24-47 with `$55` (violet), 48-71 with `$D5` (orange), 72-95
   with `$AA` (blue). Repeat the pattern down the screen. You'll
   need 96 base addresses; precompute or use the formula at
   runtime.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 9

| Want to... | Use |
|---|---|
| Switch to hi-res page 2 | `LDA $C050 : LDA $C052 : LDA $C055 : LDA $C057` |
| Switch to hi-res page 1 (only if relocated) | `LDA $C054 : LDA $C057` after enabling graphics |
| Return to text | `LDA $C051 : JSR $FC58` |
| All-white screen | Fill `$4000-$5FFF` with `$7F` |
| All-black screen | Fill `$4000-$5FFF` with `$00` |
| Solid green | Fill with `$2A`; column 0 should be `$2A` (even-aligned) |
| Solid violet | Fill with `$55` |
| Y to base address | `$4000 + (Y&7)*$400 + ((Y>>3)&7)*$80 + (Y>>6)*$28` |
| X to byte offset | `X / 7` |
| X mod byte position | `X mod 7` (which bit within the byte) |

### Color map cheat-sheet

| Pattern (one byte) | Bit 7 | Result |
|---|---|---|
| `0010 1010` (`$2A`) | 0 | Green |
| `0101 0101` (`$55`) | 0 | Violet |
| `0111 1111` (`$7F`) | 0 | White |
| `1010 1010` (`$AA`) | 1 | Blue |
| `1101 0101` (`$D5`) | 1 | Orange |
| `1111 1111` (`$FF`) | 1 | White |

Black is just `$00` regardless of bit 7. The "extra" color codes
(2 blacks, 2 whites) exist because the hardware has separate
phase tracking; for solid backgrounds either works.

### When to call the ROM anyway

If you bring along `BASIC.SYSTEM` (skip the `a2fuse rm
BASIC.SYSTEM` in your install target), the Applesoft routines
become reliable: `HGR2` initialises everything correctly, and
`HCOLOR` / `HPOSN` / `HPLOT0` / `HLIN` give you a real drawing
API. You boot to a `]` prompt, then `-MYPROG.SYSTEM` to launch.

For a serious hi-res game you'd write your own equivalents (the
ROM ones are slow), but for prototyping the ROM is the
fast-development path. The trade is: lose auto-launch, keep
BASIC. Your choice per project.
