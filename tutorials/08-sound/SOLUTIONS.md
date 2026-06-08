# Stage 8 solutions

## 1. Melody

A table of `(pitch, duration)` pairs ending with `(0, 0)`:

```
MELODY      DFB   200,80         ;C
            DFB   200,80         ;C
            DFB   134,80         ;G
            DFB   134,80         ;G
            DFB   119,80         ;A
            DFB   119,80         ;A
            DFB   134,160        ;G (long)
            DFB   0,0

PLAY_MEL    LDX   #0
:ML         LDA   MELODY,X
            BEQ   :MD
            STA   PITCH
            INX
            LDA   MELODY,X
            STA   DUR
            INX
            TXA
            PHA
            JSR   TONE
            JSR   REST
            PLA
            TAX
            JMP   :ML
:MD         RTS

REST        LDX   #$30
:R1         LDY   #0
:R2         DEY
            BNE   :R2
            DEX
            BNE   :R1
            RTS
```

We have to `PHA`/`PLA` X because `TONE` and `REST` both clobber it.
You could also keep the loop index in a zero-page byte
(`MEL_IDX`) and forget the stack dance.

## 2. Sweep

Tone with monotonically-changing PITCH. The outer loop varies
PITCH; the inner is the standard TONE.

```
SWEEP_DOWN  LDA   #50
            STA   PITCH
:SL         LDA   #4              ;short DUR per step
            STA   DUR
            JSR   TONE
            LDA   PITCH
            CLC
            ADC   #2               ;ramp PITCH up
            STA   PITCH
            CMP   #200
            BCC   :SL
            RTS
```

For ascending ("weep"): start at PITCH = 200 and DEC by 2.

Sweeps make satisfying laser/UFO sounds. With even shorter DUR per
step (say 1) and finer PITCH increments, the sweep becomes
smoother.

## 3. Footsteps in WALKER

The cheapest possible click is unrolled (no loop), about 50
microseconds:

```
* in WALKER's :MOVED, before the JMP :LOOP:
            JSR   FOOTSTEP
            JMP   :LOOP

FOOTSTEP    LDA   $C030
            LDX   #$20
:F          DEX
            BNE   :F
            LDA   $C030          ;second click
            RTS
```

One full square-wave period. Sounds like a tap.

A better-sounding footstep is two short clicks separated by a
longer silence:

```
FOOTSTEP    LDA   $C030
            LDX   #$10
:F1         DEX
            BNE   :F1
            LDA   $C030
            LDX   #$50          ;longer silence
:F2         DEX
            BNE   :F2
            LDA   $C030
            LDX   #$10
:F3         DEX
            BNE   :F3
            LDA   $C030
            RTS
```

Different `LDX` values give different "footstep voices" — vary by
row to get the player sounding like they're walking on different
surfaces. Real Apple II games like Karateka use longer sequences
to fake percussion and footsteps simultaneously.
