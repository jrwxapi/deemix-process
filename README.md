# deemix-process

Post-processes a downloaded FLAC library laid out as `Artist/Album/NN Song.flac`:

1. Cleans file and directory names — strips anything in parentheses and all punctuation (dashes are kept). Artist folders also lose a leading "The " (`The Beatles` → `Beatles`).
2. Encodes each FLAC to MP3 (`lame` CBR 320 kbps, `-q 4`) into `MP3_DEST/Artist/Album/Song.mp3`, carrying over title, artist, album, album artist, track number, disc number, year, and genre.
3. Moves the original FLAC to `FLAC_DEST/Artist/Album/Song.flac`.
4. Album art: the first `jpg`/`jpeg`/`png`/`gif` in each album folder is renamed to `cover.<ext>`, embedded in the MP3s (`lame --ti`), copied to the MP3 tree, and moved with the FLACs. If lame rejects the art (some builds cap it at 128 KB), the track is re-encoded without it.
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
