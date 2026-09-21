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
# TEST VIDEO / AUDIO
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
# IMPORTANT:
#
# The number must be the FINAL part of the stem.
#
# Therefore:
#
#     image16.jpg
#         -> 16
#
#     image16-preview.jpg
#         -> no number
#
#     Cars [66P-214MB].jpg
#         -> no number
#
#     Cars [66P-214MB]-45.jpg
#         -> 45
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
# Example:
#
#     image-045-preview.jpg
#
# becomes:
#
#     PREFIX = image-045-
#     NUMBER = 045
#     SUFFIX = preview
#
# In normal use the final number is expected to be the sequence
# number, but the function deliberately preserves any suffix.
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

  if [[ -z "$number" ]]; then
    return 1
  fi

  NUMBER_PREFIX="$working"
  LAST_NUMBER="$number"
  NUMBER_SUFFIX="$suffix"

  return 0
}

# ==============================================================
# NORMALIZE SEQUENCE PREFIX
#
# Used ONLY when comparing a numberless image against a
# numbered image.
#
# A single separator immediately before the number is ignored.
#
# Therefore these all have the same sequence key:
#
#     image
#     image-
#     image_
#     image.
#     image<space>
#
# This does NOT perform fuzzy matching.
#
# In particular:
#
#     image-preview
#
# remains different from:
#
#     image
#
# This keeps matching conservative.
# ==============================================================

normalize_sequence_prefix()
{
  local value="$1"

  # Remove ONE trailing sequence separator.
  #
  # Supported separators:
  #
  #     -
  #     _
  #     .
  #     space
  #
  value="${value%[-_. ]}"

  printf '%s' "$value"
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
  # Find largest FINAL number among normal images.
  #
  # Also build a list of sequence prefixes.
  #
  # IMPORTANT:
  #
  # The comparison prefix is normalized so that:
  #
  #     image45.jpg
  #     image-45.jpg
  #     image_45.jpg
  #     image.45.jpg
  #     image 45.jpg
  #
  # can all establish the sequence:
  #
  #     image
  #
  # But:
  #
  #     image-preview-45.jpg
  #
  # establishes:
  #
  #     image-preview
  #
  # and therefore does NOT match:
  #
  #     image.jpg
  # ==============================================================

  max_number=0
  numbered_images=0

  declare -A NUMBERED_PREFIXES=()

  while IFS= read -r -d '' file; do

    name=$(basename "$file")

    is_image "$name" || continue

    is_special_image "$name" && continue

    # ----------------------------------------------------------
    # Only recognize a number when it is the FINAL part of the
    # filename stem.
    # ----------------------------------------------------------

    if extract_last_number "$name"; then

      number="$LAST_NUMBER"

      # Safely convert leading-zero values.
      number=$((10#$number))

      numbered_images=$((numbered_images + 1))

      if (( number > max_number )); then
        max_number=$number
      fi

      # ------------------------------------------------------
      # Get the stem with the final number removed.
      #
      # Example:
      #
      #     image-45
      #
      # becomes:
      #
      #     image-
      # ------------------------------------------------------

      stem="${name%.*}"

      prefix="${stem:0:${#stem}-${#LAST_NUMBER}}"

      # ------------------------------------------------------
      # Normalize the separator immediately before the number.
      #
      # image-
      # image_
      # image.
      # image<space>
      #
      # all become:
      #
      # image
      # ------------------------------------------------------

      prefix="$(normalize_sequence_prefix "$prefix")"

      NUMBERED_PREFIXES["$prefix"]=1

    fi

  done < <(
  find "$dir" \
    -mindepth 1 \
    -maxdepth 1 \
    -type f \
    -print0
  )

  # ==========================================================
  # PASS 2
  #
  # Find numberless images that should become "01".
  #
  # Conditions:
  #
  #   1. It is an image.
  #   2. It is not a special image.
  #   3. It has NO number at the end of its stem.
  #   4. Its normalized stem exactly matches the normalized
  #      prefix of an existing numbered image.
  #
  # Example:
  #
  #     image.jpg
  #     image-45.jpg
  #     image-46.jpg
  #
  #     -> image-01.jpg
  #
  # Also:
  #
  #     image.jpg
  #     image_45.jpg
  #
  #     -> image_01.jpg
  #
  # The separator used by the existing numbered sequence is
  # preserved when constructing the new filename.
  # ==============================================================

  declare -A IMPLICIT_FIRST_IMAGES=()
  declare -A IMPLICIT_FIRST_SEPARATORS=()

  while IFS= read -r -d '' file; do

    name=$(basename "$file")

    is_image "$name" || continue

    is_special_image "$name" && continue

    stem="${name%.*}"

    # ----------------------------------------------------------
    # If the stem ends in a number, this is already a numbered
    # image and therefore cannot be the implicit first image.
    # ----------------------------------------------------------

    if [[ "$stem" =~ [0-9]$ ]]; then
      continue
    fi

    # ----------------------------------------------------------
    # Normalize the numberless stem.
    #
    # Normally this changes nothing, because there is no
    # separator before a number.
    #
    # It does allow a stem such as:
    #
    #     image-
    #
    # to match:
    #
    #     image-45.jpg
    #
    # while preserving the existing separator.
    # ----------------------------------------------------------

    normalized_stem="$(normalize_sequence_prefix "$stem")"

    # ----------------------------------------------------------
    # The COMPLETE normalized stem must match the normalized
    # prefix of an existing numbered image.
    # ----------------------------------------------------------

    if [[ -n "${NUMBERED_PREFIXES[$normalized_stem]+x}" ]]; then

      IMPLICIT_FIRST_IMAGES["$name"]=1

      # ------------------------------------------------------
      # Determine the separator used by the numberless filename.
      #
      # For:
      #
      #     image.jpg
      #
      # this is empty.
      #
      # We therefore need to discover the separator from an
      # existing numbered file later.
      # ------------------------------------------------------

    fi

  done < <(
  find "$dir" \
    -mindepth 1 \
    -maxdepth 1 \
    -type f \
    -print0
  )

  # ==========================================================
  # DETERMINE SEPARATORS FOR IMPLICIT FIRST IMAGES
  #
  # When:
  #
  #     image.jpg
  #     image-45.jpg
  #
  # exists, the new name should be:
  #
  #     image-01.jpg
  #
  # When:
  #
  #     image.jpg
  #     image_45.jpg
  #
  # exists, it should become:
  #
  #     image_01.jpg
  #
  # For a plain number:
  #
  #     image.jpg
  #     image45.jpg
  #
  # it becomes:
  #
  #     image01.jpg
  # ==============================================================

  for first_name in "${!IMPLICIT_FIRST_IMAGES[@]}"; do

    first_stem="${first_name%.*}"
    normalized_stem="$(normalize_sequence_prefix "$first_stem")"

    IMPLICIT_FIRST_SEPARATORS["$first_name"]=""

    while IFS= read -r -d '' numbered_file; do

      numbered_name=$(basename "$numbered_file")

      is_image "$numbered_name" || continue
      is_special_image "$numbered_name" && continue

      if ! extract_last_number "$numbered_name"; then
        continue
      fi

      numbered_stem="${numbered_name%.*}"

      numbered_prefix="${numbered_stem:0:${#numbered_stem}-${#LAST_NUMBER}}"

      numbered_normalized="$(normalize_sequence_prefix "$numbered_prefix")"

      if [[ "$numbered_normalized" == "$normalized_stem" ]]; then

        # ----------------------------------------------------
        # Determine the separator between prefix and number.
        # ----------------------------------------------------

        separator="${numbered_prefix:${#numbered_normalized}}"

        IMPLICIT_FIRST_SEPARATORS["$first_name"]="$separator"

        break

      fi

    done < <(
    find "$dir" \
      -mindepth 1 \
      -maxdepth 1 \
      -type f \
      -print0
    )

  done

  # ==========================================================
  # DETERMINE PADDING
  # ==============================================================

  width=$(get_number_width "$max_number")

  # An implicit first image requires at least two digits so that
  # it becomes "01".
  if (( ${#IMPLICIT_FIRST_IMAGES[@]} > 0 && width < 2 )); then
    width=2
  fi

  echo "  Numbered images:        $numbered_images"
  echo "  Largest number:         $max_number"
  echo "  Implicit first images:  ${#IMPLICIT_FIRST_IMAGES[@]}"
  echo "  Padding width:          $width"

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
      # NUMBERLESS IMAGE THAT IS REALLY IMAGE 1
      # --------------------------------------------------

      if [[ -n "${IMPLICIT_FIRST_IMAGES[$name]+x}" ]]; then

        extension=".${name##*.}"

        separator="${IMPLICIT_FIRST_SEPARATORS[$name]}"

        new_name="${name%.*}${separator}$(printf '%0*d' "$width" 1)${extension}"

        OLD_NAMES+=("$dir/$name")
        NEW_NAMES+=("$dir/$new_name")

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
        #
        # If it did not qualify as an implicit first image,
        # it keeps the existing behavior.
        # ------------------------------------------------

        OLD_NAMES+=("$dir/$name")
        NEW_NAMES+=("$dir/*$name")

      fi

      # ======================================================
      # VIDEOS / AUDIO
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
  # Temporary names therefore look like:
  #
  #     __filename_normalizer_tmp_12345_0
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
