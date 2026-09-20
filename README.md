# Number Adjust

A Bash utility that normalizes media filenames inside each subdirectory so they sort in a predictable order in file browsers and media libraries.

## What it does

The script scans every subdirectory beneath the current folder and renames files so that:

- numbered image files are padded to a consistent width based on the largest number found in that directory
- special image names such as `cover`, `wallpaper`, and `preview` are preserved in a preferred sort order
- videos are prefixed with `~` so they sort after images
- non-numbered files get a leading `*` so they sort before numbered files
- files directly in the current directory are ignored

This is useful for media collections where you want browsing order like:

- `*cover.jpg`
- `*cover2.jpg`
- `*wallpaper1.jpg`
- `*preview.jpg`
- `image01.jpg`
- `image02.jpg`
- `image10.jpg`
- `~1.mp4`
- `~2.mkv`

## Usage

From the project directory:

```bash
chmod +x Number-Adjust.sh
./Number-Adjust.sh
```

### Dry run

Preview changes without renaming files:

```bash
./Number-Adjust.sh -n
```

or

```bash
./Number-Adjust.sh --dry-run
```

## Behavior notes

- The script processes every subdirectory independently.
- It does not rename files in the top-level directory itself.
- It only touches files that are recognized as images or videos.
- It uses temporary names internally while renaming, then restores the final names safely.

## Example

If a folder contains:

```text
image1.jpg
image2.jpg
image10.jpg
video.mp4
```

it may be normalized to:

```text
image01.jpg
image02.jpg
image10.jpg
~video.mp4
```

depending on the largest numbered image in that directory.

## License

This project is provided as-is for personal use and local media organization.
