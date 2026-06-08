# Stage 10 — ProDOS MLI for file I/O

**Source:** `src/LOAD.S`
**Build:** `make PROGRAM=LOAD run` (see "Preparing the disk" below)

So far every program has been a self-contained SYS file with all
its data baked into the binary. Real applications read and write
files. ProDOS exposes a clean function-call API for that — the
*Machine Language Interface* (MLI) — at a single fixed address.

## What you'll learn

- The MLI calling convention (`JSR $BF00 : DFB cmd : DA params`)
- The OPEN/READ/CLOSE three-step for reading a file
- ProDOS path conventions (length-prefixed ASCII, absolute paths)
- The role of the I/O buffer
- How errors come back (carry flag + error byte)

## How MLI calls work

There's exactly one entry point: `$BF00`. To call any MLI function:

```
            JSR   $BF00
            DFB   cmd_byte
            DA    pointer_to_param_block
```

`$BF00` is itself the ProDOS dispatcher. It reads the byte
*following* the `JSR` (using the return address on the stack to
find it), interprets that as the command number, reads the next
two bytes as a pointer to a parameter block, adjusts the return
address to skip past these inline bytes, then dispatches to the
right handler.

On return:

- **Carry clear (BCC)**: success. Any output params (like a
  refnum) are written into the param block.
- **Carry set (BCS)**: error. A holds the error code.

You write the call inline as if those three bytes (cmd + pointer)
were instructions. They're not — they're a manifest for `$BF00`.
This is the "inline arguments after JSR" trick we discussed in
stage 4, now used by the OS itself.

## The three functions we need to read a file

### OPEN ($C8)

```
OPEN_PARMS  DFB   3              ;param count
            DA    PATHNAME       ;pointer to length-prefixed path
            DA    IOBUF          ;pointer to 1024-byte I/O buffer
            DFB   $00            ;output: file reference number
```

Param block layout:

- **Byte 0**: parameter count (3 for OPEN). Lets MLI sanity-check.
- **Bytes 1-2**: pointer to the pathname.
- **Bytes 3-4**: pointer to a 1024-byte buffer that ProDOS uses
  internally for this open file (sector buffer, position state,
  etc.). You don't touch the contents; you just provide the
  storage.
- **Byte 5**: refnum (output). After OPEN returns successfully,
  this byte is set to a 1-byte handle you pass to READ and CLOSE.

### READ ($CA)

```
READ_PARMS  DFB   4              ;param count
            DFB   refnum          ;copy from OPEN's output
            DA    BUFFER          ;destination buffer
            DA    256             ;request count
            DA    0                ;actual count (output)
```

Param block layout:

- **Byte 0**: count (4 for READ).
- **Byte 1**: refnum (input).
- **Bytes 2-3**: pointer to your destination buffer.
- **Bytes 4-5**: how many bytes you want (low/high).
- **Bytes 6-7**: how many bytes ProDOS actually transferred
  (output). Less than requested at EOF.

### CLOSE ($CC)

```
CLOSE_PARMS DFB   1              ;param count
            DFB   refnum          ;copy from OPEN's output
```

Two bytes total. CLOSE releases the I/O buffer for reuse.

You must always CLOSE every file you OPEN. Forgetting leaks the
internal slot ProDOS allocated; eventually OPEN starts returning
"too many open files" (error `$42`).

## The pathname format

ProDOS pathnames are **length-prefixed ASCII**, like:

```
PATHNAME    DFB   15
            ASC   "/WORK/HELLO.TXT"
```

First byte is the length (0-64 for full paths). The bytes after
are the path, no terminator, *plain ASCII (no high bit)*. Yes —
even though ProDOS lives on a machine where most strings have the
high bit set, MLI paths use 7-bit ASCII.

Absolute paths start with `/` followed by the volume name. The
demo uses `/WORK/HELLO.TXT` because our disk's volume name is
`WORK` (look at `make install`'s catalog output).

Relative paths (no leading `/`) are interpreted relative to the
ProDOS *prefix*, which `BASIC.SYSTEM` sets but bare SYS files do
not. For a SYS file like ours that doesn't bring along
`BASIC.SYSTEM`, always use absolute paths to be safe.

## The I/O buffer

ProDOS needs 1024 bytes of scratch per open file. You provide it.
The buffer must be:

- **1024 bytes long.**
- **Page-aligned**: starts at an address whose low byte is `$00`.
  In Merlin32, `DS \` aligns to the next page boundary.
- **In your address space**: not in ROM, not in I/O, not in the
  text page, not overlapping anything else you need to keep.

In `LOAD.S` we put it after all the code with `DS \` then `IOBUF
DS 1024`. After Merlin32 assembles, `IOBUF` lands at the next
`$xx00` boundary.

You can reuse the same buffer for sequentially-opened files (open,
read, close, open another with the same buffer, etc.). What you
can't do is open two files simultaneously with one buffer — each
open file needs its own dedicated 1024 bytes.

## Walking through `LOAD.S`

```
            JSR   MLI
            DFB   $C8
            DA    OPEN_PARMS
            BCC   :OPEN_OK
            JSR   PRINT_ERR
            JMP   :WAIT_KEY
:OPEN_OK
```

`JSR MLI` pushes the return address. ProDOS reads `$C8` and
`OPEN_PARMS` from the bytes after the JSR. If the file opens,
`OPEN_REFNUM` is set and carry is clear. We move on.

If carry was set on return, A holds the error code (e.g., `$46`
for "file not found"). `PRINT_ERR` shows it on screen so you can
look it up.

```
            LDA   OPEN_REFNUM
            STA   READ_REFNUM
            STA   CLOSE_REFNUM
```

The refnum OPEN gave us is now propagated to the other param
blocks so READ and CLOSE know which file we mean.

```
            JSR   MLI
            DFB   $CA
            DA    READ_PARMS
            BCC   :READ_OK
            ...
:READ_OK    JSR   PRINT_BUFFER
```

READ with refnum, destination, and request count = 256. ProDOS
fills the buffer (up to 256 bytes) and sets `ACTUAL_LO`/
`ACTUAL_HI` to how many it actually delivered. For a small file
the actual count is the file size; for a large file with multiple
reads, it tells you how much of the requested chunk you got.

```
PRINT_BUFFER
            LDX   #0
:PL         CPX   ACTUAL_LO
            BCS   :PD
            LDA   BUFFER,X
            ORA   #$80
            JSR   COUT
            INX
            BNE   :PL
:PD         RTS
```

Iterate up to `ACTUAL_LO` bytes (assuming `ACTUAL_HI=0` — the file
is small). Each byte goes through `COUT`, which handles `$8D`
(carriage return) by advancing the cursor to a new line. So if the
file content has CRs at the end of each line, you get visible line
breaks.

```
:CLOSE      JSR   MLI
            DFB   $CC
            DA    CLOSE_PARMS
```

Even if the READ failed, we close the file. Always close. (The
"on error skip cleanup" pattern is wrong here — we'd leak the
buffer slot.)

## Preparing the disk

The Makefile rebuilds the disk image on every install, but it only
puts your SYS file. To also put a text file:

```sh
make PROGRAM=LOAD install
a2fuse put dist/WORK.po tutorials/10-prodos/sample.txt HELLO.TXT --type '$04'
make run
```

Or copy the install line out and add the `a2fuse put` after it.
The type `$04` is "TXT" — what `LOAD.S` expects.

You could also let the Makefile do it. Add to your `install`
target:

```
install: $(BIN) image
	a2fuse put --force $(IMAGE) $(BIN) $(INSTALL_NAME) --type '$(FILE_TYPE)' --aux-type '$(LOAD_ADDR)'
	[ "$(PROGRAM)" = LOAD ] && a2fuse put --force $(IMAGE) tutorials/10-prodos/sample.txt HELLO.TXT --type '$$04' || true
```

But that's stage-specific Makefile glue. For a one-off demo, just
run the `a2fuse put` by hand.

## Error codes (the most common ones)

| Code | Meaning |
|---|---|
| `$00` | (no error; carry would be clear) |
| `$27` | I/O error (bad disk, hardware) |
| `$28` | No device connected |
| `$2B` | Disk write-protected |
| `$40` | Invalid pathname syntax |
| `$42` | Too many files open (max 8) |
| `$44` | Path not found (directory missing) |
| `$45` | Volume not found |
| `$46` | File not found |
| `$47` | Duplicate file (on CREATE) |
| `$48` | Volume full |
| `$49` | Directory full |
| `$4E` | Access not permitted |
| `$50` | File already open |

The most common pair you'll see during development: `$46` (file
doesn't exist on disk) and `$40` (your pathname has a typo or
isn't length-prefixed properly).

## Exercises

1. **CREATE then WRITE then CLOSE.** Add code that creates
   `/WORK/OUTPUT.TXT` (`$C0` is CREATE, `$CB` is WRITE), writes a
   short message into it, then closes. After `make run`,
   `a2fuse catalog dist/WORK.po` should show the new file.
2. **Hex dump.** Open `/WORK/BOUNCE.SYSTEM` (or any binary on the
   disk), read 64 bytes, and print each as a 2-digit hex value
   with a space between. You'll need the hex printer from stage 6.
3. **Handle file-not-found gracefully.** Change the pathname to a
   file that doesn't exist. The error path now runs. What's the
   error code on screen? Verify against the table above.

Solutions in [SOLUTIONS.md](SOLUTIONS.md).

## Cheat sheet for stage 10

| Want to... | Use |
|---|---|
| Call MLI | `JSR $BF00 : DFB cmd : DA params` |
| Detect error | `BCS` after the call; A has code |
| Open a file | cmd `$C8`, params: count(1), path(2), iobuf(2), refnum(1) |
| Read a file | cmd `$CA`, params: count(1), refnum(1), buf(2), req(2), got(2) |
| Close a file | cmd `$CC`, params: count(1), refnum(1) |
| Create a file | cmd `$C0` |
| Write to a file | cmd `$CB` |
| Destroy (delete) | cmd `$C1` |
| Rename | cmd `$C2` |
| Pathname format | length byte + 7-bit ASCII, max 64 chars |
| I/O buffer | 1024 bytes, page-aligned, one per open file |

### MLI command quick-reference

| Cmd | Name | Param count |
|---|---|---|
| `$80` | READ_BLOCK | 3 |
| `$81` | WRITE_BLOCK | 3 |
| `$82` | GET_TIME | 0 |
| `$C0` | CREATE | 7 |
| `$C1` | DESTROY | 1 |
| `$C2` | RENAME | 2 |
| `$C3` | SET_FILE_INFO | 7 |
| `$C4` | GET_FILE_INFO | 10 |
| `$C5` | ONLINE | 2 |
| `$C6` | SET_PREFIX | 1 |
| `$C7` | GET_PREFIX | 1 |
| `$C8` | OPEN | 3 |
| `$C9` | NEWLINE | 3 |
| `$CA` | READ | 4 |
| `$CB` | WRITE | 4 |
| `$CC` | CLOSE | 1 |
| `$CD` | FLUSH | 1 |
| `$CE` | SET_MARK | 2 |
| `$CF` | GET_MARK | 2 |
| `$D0` | SET_EOF | 2 |
| `$D1` | GET_EOF | 2 |
| `$D2` | SET_BUF | 2 |
| `$D3` | GET_BUF | 2 |
