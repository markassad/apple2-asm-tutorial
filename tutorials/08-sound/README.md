# Stage 8 — The speaker and sound

**Source:** `src/BEEP.S`
**Build:** `make PROGRAM=BEEP run`

The Apple II speaker is a single-bit DAC: there's no waveform
generator, no envelope, no sample memory. It's literally a metal
cone wired to a flip-flop that toggles each time the CPU touches
one specific address. *Your code is the audio.* Periodicity = pitch.
Number of periods = duration.

## What you'll learn

- How `$C030` actually works (and why it's *one* address, not two)
- Generating a square wave by hand
- The relationship between cycles, periods, and audible frequency
- A reusable `TONE(pitch, duration)` subroutine

## $C030 is a flip-flop

Every time the CPU does *any* access to `$C030` — `LDA $C030`, `STA
$C030`, even `BIT $C030` — the speaker bit toggles. From silent
state to clicked, or from clicked to silent.

The byte you read back from `$C030` is undefined; you're not
reading audio. You're using the *side effect* of the read.

To produce a tone:

1. Toggle the speaker.
2. Wait some number of CPU cycles.
3. Toggle again.
4. Wait again.
5. Repeat for as long as you want the tone to last.

Each toggle is half a period. Two toggles = one full cycle = one
period of the resulting square wave. Frequency = `1 / period`. So
if you wait for `N` cycles between toggles, period = `2N` cycles,
and at a 1.023 MHz clock:

```
f (Hz) = 1023000 / (2 * N)
```

`N = 1000` cycles → 511 Hz (just above middle C).
`N = 500` cycles → 1023 Hz (about two octaves above middle C).
`N = 4000` cycles → 128 Hz (one octave below middle C).

The audible range is roughly 20 Hz to 20 kHz; you can play notes
from `N ≈ 25000` (about 20 Hz, a very low rumble) to `N ≈ 25` (the
top of human hearing). The fastest you can toggle is limited by
the inner-loop overhead — a few hundred cycles minimum.

## How `BEEP.S` does it

```
TONE
:CYC        LDA   SPEAKER       ;click  (4 cycles)
            LDX   PITCH         ;       (3 cycles)
:WP         DEX                 ;       (2 cycles)
            BNE   :WP           ;       (3 cycles, taken)
            DEC   DUR           ;       (5 cycles)
            BNE   :CYC          ;       (3 cycles, taken)
            RTS
```

Per half-cycle: `LDA SPEAKER` (4) + `LDX PITCH` (3) + `PITCH *
(DEX + BNE)` = `PITCH * 5` + `DEC DUR` (5) + `BNE` (3) = roughly
`5 * PITCH + 15` cycles.

For `PITCH = 200`: half-period ≈ `5*200 + 15` = 1015 cycles.
Frequency ≈ `1023000 / (2 * 1015)` ≈ 504 Hz. About B4 (1 below
middle C is C4 = 261 Hz, so 504 Hz is roughly B4 / a bit higher).

For `PITCH = 100`: half-period ≈ 515. Frequency ≈ 993 Hz. About B5.

Roughly one octave higher per halving of `PITCH`. Hence the
`PITCHES` table in `BEEP.S` covers 8 notes from 200 down to 100, a
rough C-major scale.

`DUR` controls how long the tone plays. Each half-cycle is about
1000 cycles. `DUR = 80` → 80,000 cycles ≈ 78 ms. Long enough to
clearly hear; short enough to feel snappy.

To play a *longer* tone you'd need `DUR > 255`. Either widen `DUR`
to 16 bits (and decrement low / borrow into high), or call `TONE`
several times in a row at the same pitch.

## Why no envelope, no waveform shaping?

Because the speaker doesn't have one. It's a single bit. Toggling
fast gives a high-pitched square wave; toggling slow gives a
low-pitched square wave. You can't make a sine. You can't make a
sawtooth. You can't fade in or fade out.

But you can *approximate* envelope-shaped waveforms by *modulating
the duty cycle* — making "on" pulses longer or shorter than "off"
pulses. Skilled Apple II coders in the late 80s produced
remarkable sample-like audio this way, calling 4-bit "engines"
that loaded pre-computed waveform tables and pulse-width-modulated
the speaker at thousands of Hz. The Apple II Mockingboard add-on
card was the eventual answer — it had real audio synthesis chips —
but the unaided base machine has just `$C030`.

## Why the speaker can't play two notes at once

One bit, one cone. To approximate polyphony, you interleave: play
half a period of note A, half of note B, etc. The result is
distortion-laden but recognizably two-note. The Karateka game's
title music does this. It works because the cone integrates the
fast toggling into something resembling additive synthesis.

For our scale demo, monophonic is fine.

## The interactive loop

```
:LOOP       LDA   KBD
            BPL   :LOOP
            STA   KBDSTRB
            AND   #$7F
            CMP   #$1B
            BEQ   :QUIT
            CMP   #'1'
            BCC   :LOOP
            CMP   #'8'+1
            BCS   :LOOP
            SEC
            SBC   #'1'
            TAX
            LDA   PITCHES,X
            STA   PITCH
            LDA   #80
            STA   DUR
            JSR   TONE
            JMP   :LOOP
```

Standard keyboard polling, then:

- ESC → exit.
- `'1'` through `'8'` → index 0..7 → look up `PITCHES,X` → play.
- anything else → ignore.

`AND #$7F` strips the high bit so we can compare against literal
character constants without writing `'1'+$80` everywhere. (Either
convention works; this one keeps the code looking more like the C
you might be used to.)

## Exercises

1. **Play a melody.** Add a `MELODY` table holding pairs of
   `(pitch, duration)`. Walk it and call `TONE` for each entry,
   with a short silent pause between notes. Stop when you hit a
   `(0, 0)` sentinel. Try the opening of "Twinkle Twinkle Little
   Star": pitches 200, 200, 134, 134, 119, 119, 134.
2. **Sweep.** Play a tone whose `PITCH` starts at 50 and increases
   by 5 every `DUR` half-cycles, until `PITCH` reaches 200. The
   result is a descending sweep ("woop"). Make a second version
   that goes the other way (ascending: "weep").
3. **Footstep sounds in WALKER.** Combine with stage 6: every time
   the '@' moves, play a brief click. Hint: one or two cycles of
   `LDA $C030 : LDX #50 : :W DEX : BNE :W` is enough for a short
   blip. Be careful not to call `TONE` with `DUR = 80` per step,
   or the program becomes unresponsive — the move loop blocks
   until the tone finishes.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 8

| Want to... | Use |
|---|---|
| Toggle the speaker once | Read or write any address starting with `$C030` |
| Higher pitch | Smaller inner-loop count between toggles |
| Lower pitch | Larger inner-loop count |
| Longer note | More outer-loop iterations |
| Frequency formula | `f = 1023000 / (2 * cycles_per_half_period)` |
| Octave up | Halve the inner count |
| Octave down | Double the inner count |

### Approximate pitch table

If you want to hit specific musical pitches at the 1.023 MHz Apple
II clock with the `BEEP.S` inner loop (≈ `5*PITCH + 15` cycles per
half-period), these `PITCH` values get you close:

| Note | Hz | PITCH |
|---|---|---|
| C4 (middle C) | 262 | 388 |
| C5 | 524 | 192 |
| C6 | 1047 | 95 |
| A4 (concert A) | 440 | 230 |
| A5 | 880 | 113 |

`PITCH > 255` doesn't fit in a single byte, so for notes lower than
C5 you'd either widen `PITCH` to 16 bits or use a different
inner-loop structure.
