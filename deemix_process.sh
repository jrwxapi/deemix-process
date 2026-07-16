#!/usr/bin/env bash
#
# deemix_process.sh — clean names and process a downloaded FLAC library.
#
# Expects a Source tree laid out as Artist/Album/NN Song.flac (plus an
# optional cover.jpg per album), then:
#
#   1. Strips anything in (parentheses) from file and directory names.
#   2. Strips remaining punctuation (dashes are kept); artist folders also
#      lose a leading "The " (The Beatles -> Beatles).
#   3. Encodes each .flac to mp3 (lame CBR 320 kbps, -q 4), preserving tags,
#      into MP3_DEST/Artist/Album/Song.mp3
#   4. Moves the original .flac to FLAC_DEST/Artist/Album/Song.flac
#   cover.jpg is copied into the mp3 album dir and moved with the FLACs.
#
# Duplicate handling: within a destination album dir a track is identified by
# its leading two-digit track number ("NN ..."). Any existing file with the
# same NN but a different (older/misspelled) name is removed before writing.
# Source files/dirs are deleted once both the mp3 and the flac exist at
# their destinations; every deletion is printed to the terminal.
#
# Prerequisites: flac and lame (e.g. sudo apt install lame flac).
# Set the three directory variables below before first use.
#
# Usage:  deemix_process.sh [--dry-run]

set -u

SRC="/path/to/source"        # incoming Artist/Album/*.flac tree
MP3_DEST="/path/to/mp3"      # mp3 library root
FLAC_DEST="/path/to/flac"    # flac library root

for d in "$SRC" "$MP3_DEST" "$FLAC_DEST"; do
    [[ "$d" == /path/to/* || ! -d "$d" ]] && { echo "ERROR: directory '$d' not set or missing — edit SRC/MP3_DEST/FLAC_DEST at the top of this script." >&2; exit 1; }
done
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

for bin in flac metaflac lame; do
    command -v "$bin" >/dev/null || { echo "ERROR: '$bin' not found. Install with: sudo apt install lame flac" >&2; exit 1; }
done

skipped=0
encoded=0
moved=0
failed=0
deduped=0
cleaned=0

# Remove (...) groups, then all punctuation except dashes, collapse spaces,
# trim leading/trailing spaces and dashes.
clean_name() {
    sed -E 's/\([^)]*\)//g;
            s/[^[:alnum:][:space:]-]//g;
            s/[[:space:]]+/ /g;
            s/^[- ]+//; s/[- ]+$//' <<<"$1"
}

# Print the value of a FLAC tag, empty if absent.
flac_tag() {
    metaflac --show-tag="$2" "$1" 2>/dev/null | head -n1 | cut -d= -f2-
}

run() {
    if (( DRY_RUN )); then
        echo "DRY: $*"
    else
        "$@"
    fi
}

# Remove files in dir $1 that share the leading "NN " track-number prefix of
# name $2 (extension $3) but are spelled differently — stale duplicates.
dedupe_track() {
    local dir="$1" want="$2" ext="$3" old
    [[ "$want" =~ ^[0-9]{2}\  ]] || return 0
    for old in "$dir/${want:0:2} "*."$ext"; do
        [[ "$(basename "$old")" == "$want.$ext" ]] && continue
        echo "RM (dup ${want:0:2}): $old"
        run rm -f "$old"
        (( deduped++ ))
    done
    return 0
}

encode_mp3() {
    local src="$1" dst="$2"
    local title artist album track date
    title=$(flac_tag "$src" TITLE)
    artist=$(flac_tag "$src" ARTIST)
    album=$(flac_tag "$src" ALBUM)
    track=$(flac_tag "$src" TRACKNUMBER)
    date=$(flac_tag "$src" DATE)

    local -a tagargs=(--add-id3v2)
    [[ -n "$title"  ]] && tagargs+=(--tt "$title")
    [[ -n "$artist" ]] && tagargs+=(--ta "$artist")
    [[ -n "$album"  ]] && tagargs+=(--tl "$album")
    [[ -n "$track"  ]] && tagargs+=(--tn "$track")
    [[ -n "$date"   ]] && tagargs+=(--ty "${date:0:4}")

    if (( DRY_RUN )); then
        echo "DRY: encode '$src' -> '$dst'"
        return 0
    fi
    flac -dcs "$src" | lame --quiet -b 320 --cbr -q 4 "${tagargs[@]}" - "$dst"
    local st=("${PIPESTATUS[@]}")
    if (( st[0] != 0 || st[1] != 0 )); then
        rm -f "$dst"
        return 1
    fi
}

shopt -s nullglob

for artist_dir in "$SRC"/*/; do
    artist=$(basename "$artist_dir")
    c_artist=$(clean_name "$artist")
    [[ -n "$c_artist" ]] || c_artist="$artist"
    # Strip leading "The " from artist folders (The Beatles -> Beatles)
    [[ "$c_artist" =~ ^[Tt]he\ (.+)$ ]] && c_artist="${BASH_REMATCH[1]}"

    for album_dir in "$artist_dir"*/; do
        album=$(basename "$album_dir")
        c_album=$(clean_name "$album")
        [[ -n "$c_album" ]] || c_album="$album"

        mp3_album_dir="$MP3_DEST/$c_artist/$c_album"
        flac_album_dir="$FLAC_DEST/$c_artist/$c_album"
        run mkdir -p "$mp3_album_dir" "$flac_album_dir"

        for f in "$album_dir"*.flac; do
            name=$(basename "$f" .flac)
            c_name=$(clean_name "$name")
            [[ -n "$c_name" ]] || c_name="$name"

            mp3_out="$mp3_album_dir/$c_name.mp3"
            flac_out="$flac_album_dir/$c_name.flac"

            dedupe_track "$mp3_album_dir" "$c_name" mp3
            dedupe_track "$flac_album_dir" "$c_name" flac

            if [[ -e "$mp3_out" ]]; then
                echo "SKIP (exists): $mp3_out"
                (( skipped++ ))
            elif encode_mp3 "$f" "$mp3_out"; then
                echo "MP3:  $mp3_out"
                (( encoded++ ))
            else
                echo "FAIL: encoding '$f' — original left in place" >&2
                (( failed++ ))
                continue
            fi

            if [[ -e "$flac_out" ]]; then
                echo "SKIP (exists): $flac_out"
                (( skipped++ ))
            else
                run mv "$f" "$flac_out" && (( moved++ ))
            fi

            # Both destinations hold the track; drop the source if it remains.
            if [[ -e "$f" && -e "$mp3_out" && -e "$flac_out" ]]; then
                echo "RM (source, both exist): $f"
                run rm -f "$f"
                (( cleaned++ ))
            fi
        done

        # Cover art: copy into the Mp3 tree, move with the FLACs.
        if [[ -f "$album_dir/cover.jpg" ]]; then
            if [[ ! -e "$mp3_album_dir/cover.jpg" ]]; then
                run cp "$album_dir/cover.jpg" "$mp3_album_dir/cover.jpg"
            fi
            if [[ ! -e "$flac_album_dir/cover.jpg" ]]; then
                run mv "$album_dir/cover.jpg" "$flac_album_dir/cover.jpg"
            fi
            if [[ -f "$album_dir/cover.jpg" && -e "$mp3_album_dir/cover.jpg" && -e "$flac_album_dir/cover.jpg" ]]; then
                echo "RM (source cover, both exist): $album_dir/cover.jpg"
                run rm -f "$album_dir/cover.jpg"
            fi
        fi

        (( DRY_RUN )) || { rmdir "$album_dir" 2>/dev/null && echo "RMDIR: $album_dir"; }
    done
    (( DRY_RUN )) || { rmdir "$artist_dir" 2>/dev/null && echo "RMDIR: $artist_dir"; }
done

echo
echo "Done: $encoded encoded, $moved flacs moved, $deduped dest duplicates removed, $cleaned sources removed, $skipped skipped, $failed failed."
(( failed == 0 ))
