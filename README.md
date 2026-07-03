# deemix-process

Post-processes a downloaded FLAC library laid out as `Artist/Album/NN Song.flac`:

1. Cleans file and directory names — strips anything in parentheses and all punctuation (dashes are kept).
2. Encodes each FLAC to MP3 (`lame` CBR 320 kbps, `-q 4`), preserving tags, into `MP3_DEST/Artist/Album/Song.mp3`.
3. Moves the original FLAC to `FLAC_DEST/Artist/Album/Song.flac`; `cover.jpg` is copied to the MP3 tree and moved with the FLACs.
4. Dedupes destination albums by leading two-digit track number, removing older/misspelled variants of the same track.
5. Deletes sources once both the MP3 and FLAC exist at their destinations, printing every deletion.

## Setup

**Prerequisites:** `flac` and `lame` must be installed (`sudo apt install lame flac`).

**Configuration:** edit the three placeholder variables at the top of `deemix_process.sh` before first use — the script refuses to run until they point at real directories:

```bash
SRC="/path/to/source"        # incoming Artist/Album/*.flac tree
MP3_DEST="/path/to/mp3"      # mp3 library root
FLAC_DEST="/path/to/flac"    # flac library root
```

## Usage

```bash
./deemix_process.sh --dry-run   # preview every action, touches nothing
./deemix_process.sh             # the real thing
```
