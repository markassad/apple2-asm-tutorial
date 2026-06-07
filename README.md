# apple2-asm

A small workspace for writing 6502 assembly for the Apple IIe.

The loop is: edit `src/*.S` -> `make run`, which assembles with Merlin32,
packs the binary onto a bootable ProDOS image with `a2fuse`, and boots the
image in MAME's `apple2e` driver.

## Prerequisites

All three tools must be on `PATH`:

- **Merlin32** — the assembler. Build from
  [Brutal Deluxe's repo](https://github.com/apple2accumulator/merlin32)
  or download a binary; drop it somewhere on `PATH`.
- **a2fuse** — `cargo install --path ~/src/a2fuse` (or wherever this clone lives).
- **MAME** — only required for `make run`:

  ```sh
  brew install mame
  ```

  You also need the `apple2e` ROM set. MAME will tell you which files it
  expects when you first try to boot. Put them in your MAME `roms/`
  directory (`~/Library/Application Support/mame/roms` is a typical
  location on macOS).

The first `make install` triggers `a2fuse create --bootable`, which
downloads and caches the upstream ProDOS 2.4.3 image (a few hundred KB).
Subsequent builds reuse the cache.

## Daily loop

```sh
make build                 # assemble src/$(PROGRAM).S -> build/$(PROGRAM)
make install               # also rebuild dist/WORK.po with $(INSTALL_NAME) on it
make run                   # also boot apple2e with the image in drive 1
make PROGRAM=HELLO run     # build/install/boot a different source
```

`make` on its own is `make install`. `make run` first runs
`roms-check` to verify your `~/mame/roms/apple2e.zip` is good.

The default sample is `src/BOUNCE.S`, a ProDOS SYS file (type `$FF`,
load address `$2000`) installed as `BOUNCE.SYSTEM`. The `image`
target deletes `BASIC.SYSTEM` from the image so ProDOS finds our SYS
file first and auto-launches it at boot. No BASIC prompt, no manual
`BRUN` -- power on the emulator and the program runs.

`BOUNCE` clears the screen, prints a quit hint, and bounces
`HELLO, APPLE IIE!` diagonally around the 40x24 text page. Press any
key and it clears the screen and reboots via the Disk II ROM
(`$C600`).

`make install` rebuilds the disk image from scratch on every run, so
the only SYS file on it is the one you just specified. If you want
multiple SYS files (rare), customise the `install` target by hand.

## Tutorial

There's a staged tutorial in [`tutorials/`](tutorials/README.md) that
walks from "anatomy of a SYS file" up to a complete small game.
Each stage is self-contained: a walkthrough README, the source file
(in `src/`), and a worked-solutions file.

To work through a stage, the README tells you something like
`make PROGRAM=FILL run` -- the workspace is set up so the override
on the command line is all you need to switch which program builds
and boots.

## Layout

```
src/                Merlin32 sources, one program per file
tutorials/          per-stage walkthroughs + exercises
build/              assembled raw binaries (gitignored)
dist/               ProDOS disk images (gitignored)
Makefile            build, install, run, clean targets
```

## Notes on the toolchain

- Merlin32 writes its binary beside the source, named after the source
  minus the `.S` extension. The Makefile assembles inside `build/` so
  the source tree stays clean.
- Merlin32 also drops a `_FileInformation.txt` recording ProDOS type and
  aux address. The Makefile deletes it — `a2fuse put` is given the same
  values explicitly so the source of truth stays in the Makefile. Keep
  the `TYP` and `ORG` lines in the source synced with `FILE_TYPE` and
  `LOAD_ADDR` in the Makefile (Merlin32 won't catch a mismatch; ProDOS
  will refuse to load).
- `a2fuse catalog` runs after every install so you can see the file
  type, aux, and block usage of what just got written.
- MAME's `apple2e` boots from `-flop1` automatically. `-skip_gameinfo`
  hides the legal screen; remove if you'd rather see it.
- **Merlin32 inline comments need a `;`.** Spaces between the operand
  and a comment don't terminate the operand -- Merlin32 collapses
  internal whitespace and tries to parse the comment as part of the
  expression. `LDA #$80  the high bit` fails; `LDA #$80  ;the high bit`
  works.

## Headless smoke test

To verify a build runs without launching the emulator window:

```sh
mkdir -p /tmp/a2snap
mame apple2e -rompath ~/mame/roms -flop1 dist/WORK.po \
     -skip_gameinfo -nothrottle -video none \
     -seconds_to_run 20 \
     -snapshot_directory /tmp/a2snap -snapname bounce
open /tmp/a2snap/bounce.png
```

20 emulated seconds is enough for ProDOS to boot and the demo to start
animating. `-video none` skips the display backend so this runs in any
terminal.

## License

MIT, see [LICENSE](LICENSE).
