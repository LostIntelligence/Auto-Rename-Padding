#!/bin/bash

set -euo pipefail

# ==============================================================
# MEDIA FILENAME NORMALIZER
#
# Run from the top-level directory:
#
#     ./fix-media-names.sh
#
# Dry run:
#
#     ./fix-media-names.sh -n
#
# Every SUBDIRECTORY is processed independently.
#
# IMPORTANT:
#     Files directly inside the top-level directory are NOT
#     processed. Only directories below the directory where
#     this script is run are processed.
#
# Ordering intended for a filename-sorting photo viewer:
#
#     *cover.jpg
#     *cover2.jpg
#     *wallpaper1.jpg
#     *preview.jpg
#     image01.jpg
#     image02.jpg
#     image10.jpg
#     ~1.mp4
#     ~2.mkv
#
# ==============================================================


# ==============================================================
# OPTIONS
# ==============================================================

DRY_RUN=false

if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi


# ==============================================================
# IMAGE EXTENSIONS
# ==============================================================

IMAGE_EXTENSIONS=(
    jpg
    jpeg
    png
    gif
    webp
    bmp
    tif
    tiff
    avif
    heic
    heif
)


# ==============================================================
# VIDEO EXTENSIONS
# ==============================================================

VIDEO_EXTENSIONS=(
    mp4
    mkv
    avi
    mov
    m4v
    webm
    mpg
    mpeg
    ts
    m2ts
    mts
    flv
    wmv
    ogv
)


# ==============================================================
# AUDIO EXTENSIONS
# ==============================================================

AUDIO_EXTENSIONS=(
    m4a
    mp3
    flac
    ogg
    opus
    wav
    aac
)



# ==============================================================
# SPECIAL IMAGE PREFIXES
# ==============================================================

SPECIAL_PREFIXES=(
    cover
    wallpaper
    preview
)


# ==============================================================
# TEST IMAGE
# ==============================================================

is_image()
{
    local file="$1"
    local ext="${file##*.}"

    [[ "$file" == "$ext" ]] && return 1

    ext="${ext,,}"

    for allowed in "${IMAGE_EXTENSIONS[@]}"; do
        [[ "$ext" == "$allowed" ]] && return 0
    done

    return 1
}


# ==============================================================
# TEST VIDEO
# ==============================================================

is_video_or_audio()
{
    local file="$1"
    local ext="${file##*.}"

    [[ "$file" == "$ext" ]] && return 1

    ext="${ext,,}"

    for allowed in "${VIDEO_EXTENSIONS[@]}"; do
        [[ "$ext" == "$allowed" ]] && return 0
    done

    for allowed in "${AUDIO_EXTENSIONS[@]}"; do
        [[ "$ext" == "$allowed" ]] && return 0
    done

    return 1
}


# ==============================================================
# TEST SPECIAL IMAGE
# ==============================================================

is_special_image()
{
    local name="$1"
    local base="${name%.*}"
    local lower_base="${base,,}"
    local prefix

    for prefix in "${SPECIAL_PREFIXES[@]}"; do

        if [[ "$lower_base" == "$prefix" ]] ||
           [[ "$lower_base" =~ ^${prefix}([0-9]+|[^[:alnum:]].*)$ ]]; then
            return 0
        fi

    done

    return 1
}


# ==============================================================
# EXTRACT LAST NUMBER
#
# Finds the LAST contiguous sequence of digits in the filename
# stem.
#
# Examples:
#
#   image47.jpg
#       -> 47
#
#   image103.jpg
#       -> 103
#
#   ser01_img12.png
#       -> 12
#
#   im (01).png
#       -> 01
#
#   漫画第9页.png
#       -> 9
#
#   foo123bar456.jpg
#       -> 456
#
# ==============================================================

extract_last_number()
{
    local name="$1"
    local stem="${name%.*}"
    local reversed

    LAST_NUMBER=""

    reversed=$(printf '%s' "$stem" | rev)

    if [[ "$reversed" =~ ^([0-9]+) ]]; then

        LAST_NUMBER=$(printf '%s' "${BASH_REMATCH[1]}" | rev)

        return 0
    fi

    return 1
}


# ==============================================================
# SPLIT LAST NUMBER
#
# Finds the FINAL contiguous sequence of digits in the filename
# stem and splits it into:
#
#     PREFIX + NUMBER + SUFFIX
#
# ==============================================================

split_last_number()
{
    local name="$1"
    local stem="${name%.*}"
    local working="$stem"
    local suffix=""
    local number=""
    local char

    NUMBER_PREFIX=""
    LAST_NUMBER=""
    NUMBER_SUFFIX=""

    # ----------------------------------------------------------
    # Step 1:
    # Remove non-digit characters from the END.
    # ----------------------------------------------------------

    while [[ -n "$working" ]]; do

        char="${working: -1}"

        if [[ "$char" =~ [0-9] ]]; then
            break
        fi

        suffix="${char}${suffix}"
        working="${working:0:${#working}-1}"

    done


    # ----------------------------------------------------------
    # No digit at the end means there is no final number.
    # ----------------------------------------------------------

    if [[ -z "$working" ]]; then
        return 1
    fi


    # ----------------------------------------------------------
    # Step 2:
    # Remove the final contiguous digit sequence.
    # ----------------------------------------------------------

    while [[ -n "$working" ]]; do

        char="${working: -1}"

        if [[ ! "$char" =~ [0-9] ]]; then
            break
        fi

        number="${char}${number}"
        working="${working:0:${#working}-1}"

    done


    # ----------------------------------------------------------
    # A number must have been found.
    # ----------------------------------------------------------

    if [[ -z "$number" ]]; then
        return 1
    fi


    # ----------------------------------------------------------
    # Results.
    # ----------------------------------------------------------

    NUMBER_PREFIX="$working"
    LAST_NUMBER="$number"
    NUMBER_SUFFIX="$suffix"

    return 0
}


# ==============================================================
# DETERMINE NUMBER WIDTH
# ==============================================================

get_number_width()
{
    local number="$1"

    if (( number > 0 )); then
        printf '%s' "${#number}"
    else
        printf '0'
    fi
}


# ==============================================================
# PROCESS EVERY SUBDIRECTORY
#
# IMPORTANT:
#
#   -mindepth 1
#
# prevents the initial "." from being returned by find.
#
# Therefore:
#
#     ./file.jpg
#
# is ignored, while:
#
#     ./folder/file.jpg
#
# is processed.
# ==============================================================

find . \
    -mindepth 1 \
    -type d \
    -print0 |
while IFS= read -r -d '' dir; do

    echo
    echo "============================================================"
    echo "Directory: $dir"
    echo "============================================================"


    # ==========================================================
    # PASS 1
    #
    # Find largest final number among normal images.
    # ==============================================================

    max_number=0
    numbered_images=0

    while IFS= read -r -d '' file; do

        name=$(basename "$file")

        is_image "$name" || continue

        is_special_image "$name" && continue

        if extract_last_number "$name"; then

            number="$LAST_NUMBER"

            # Safely convert leading-zero values.
            number=$((10#$number))

            numbered_images=$((numbered_images + 1))

            if (( number > max_number )); then
                max_number=$number
            fi

        fi

    done < <(
        find "$dir" \
            -mindepth 1 \
            -maxdepth 1 \
            -type f \
            -print0
    )


    # ==========================================================
    # DETERMINE PADDING
    # ==============================================================

    width=$(get_number_width "$max_number")

    echo "  Numbered images: $numbered_images"
    echo "  Largest number:  $max_number"
    echo "  Padding width:   $width"


    # ==========================================================
    # BUILD RENAME LIST
    # ==============================================================

    declare -a OLD_NAMES=()
    declare -a NEW_NAMES=()

    while IFS= read -r -d '' file; do

        name=$(basename "$file")


        # ------------------------------------------------------
        # Already processed.
        # ------------------------------------------------------

        if [[ "$name" == \** || "$name" == \~* ]]; then
            continue
        fi


        # ======================================================
        # IMAGES
        # ======================================================

        if is_image "$name"; then


            # --------------------------------------------------
            # SPECIAL IMAGE
            # --------------------------------------------------

            if is_special_image "$name"; then

                OLD_NAMES+=("$dir/$name")
                NEW_NAMES+=("$dir/*$name")

                continue
            fi


            # --------------------------------------------------
            # NORMAL NUMBERED IMAGE
            # --------------------------------------------------

            if split_last_number "$name"; then

                prefix="$NUMBER_PREFIX"
                number="$LAST_NUMBER"
                suffix="$NUMBER_SUFFIX"

                extension=".${name##*.}"

                # Convert safely to decimal.
                number=$((10#$number))


                if (( width > 0 )); then
                    padded=$(printf "%0*d" "$width" "$number")
                else
                    padded="$number"
                fi


                new_name="${prefix}${padded}${suffix}${extension}"


                if [[ "$name" != "$new_name" ]]; then

                    OLD_NAMES+=("$dir/$name")
                    NEW_NAMES+=("$dir/$new_name")

                fi

            else

                # ------------------------------------------------
                # Non-numbered normal image.
                # ------------------------------------------------

                OLD_NAMES+=("$dir/$name")
                NEW_NAMES+=("$dir/*$name")

            fi


        # ======================================================
        # VIDEOS
        # ======================================================

        elif is_video_or_audio "$name"; then

            OLD_NAMES+=("$dir/$name")
            NEW_NAMES+=("$dir/~$name")


        # ======================================================
        # EVERYTHING ELSE
        # ======================================================

        else

            OLD_NAMES+=("$dir/$name")
            NEW_NAMES+=("$dir/*$name")

        fi

    done < <(
        find "$dir" \
            -mindepth 1 \
            -maxdepth 1 \
            -type f \
            -print0
    )


    # ==========================================================
    # NOTHING TO DO
    # ==============================================================

    if (( ${#OLD_NAMES[@]} == 0 )); then
        echo "  Nothing to rename."
        continue
    fi


    # ==========================================================
    # DRY RUN
    # ==============================================================

    if "$DRY_RUN"; then

        echo
        echo "  Planned changes:"

        for (( i=0; i<${#OLD_NAMES[@]}; i++ )); do

            echo "    ${OLD_NAMES[$i]}"
            echo "      -> ${NEW_NAMES[$i]}"

        done

        continue
    fi


    # ==========================================================
    # TEMPORARY RENAMES
    #
    # IMPORTANT:
    #
    # Do NOT use a leading "." or a ".tmp" extension here.
    #
    # This script operates on SMB shares, where dot-prefixed
    # names and temporary-looking files can interact badly with
    # Windows/SMB hidden-file handling.
    #
    # Temporary names therefore look like:
    #
    #     __filename_normalizer_tmp_12345_0
    #
    # rather than:
    #
    #     .filename-normalizer-12345-0.tmp
    #
    # ==============================================================

    declare -a TEMP_NAMES=()

for (( i=0; i<${#OLD_NAMES[@]}; i++ )); do

    old="${OLD_NAMES[$i]}"

    temp="$dir/__filename_normalizer_tmp_${RANDOM}_${i}"

    while [[ -e "$temp" || -L "$temp" ]]; do
        temp="$dir/__filename_normalizer_tmp_${RANDOM}_${i}"
    done

    TEMP_NAMES+=("$temp")

    mv -- "$old" "$temp"

done



    # ==========================================================
    # FINAL RENAMES
    # ==============================================================

    for (( i=0; i<${#TEMP_NAMES[@]}; i++ )); do

        temp="${TEMP_NAMES[$i]}"
        new="${NEW_NAMES[$i]}"


        if [[ -e "$new" || -L "$new" ]]; then

            echo "    WARNING - target already exists:"
            echo "      $new"
            echo "    Temporary file left untouched:"
            echo "      $temp"

        else

            echo "    $(basename "$temp")"
            echo "      -> $(basename "$new")"

            mv -- "$temp" "$new"

        fi

    done

done


echo
echo "============================================================"

if "$DRY_RUN"; then
    echo "DRY RUN COMPLETE - no files were changed."
else
    echo "DONE."
fi

echo "============================================================"
