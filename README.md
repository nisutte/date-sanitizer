# Date Sanitizer

A Perl script for sanitizing and correcting date/time metadata in image and video files by finding and setting the earliest valid date from all available date fields.

## Overview

`date-sanitize.pl` scans image and video files for all date/time metadata fields, identifies the earliest valid date, and updates the authoritative date field accordingly — `EXIF:DateTimeOriginal` for images, `QuickTime:CreateDate`/`ModifyDate` and Apple's `Keys:CreationDate` for videos. This is particularly useful for:

- Correcting timestamps in photos and videos from cameras with incorrect date/time settings
- Consolidating multiple conflicting date fields into a single authoritative timestamp
- Making media display with the correct date after importing to an iPhone (e.g. via the Apple Devices app on Windows)
- Batch processing media collections with inconsistent metadata

## Requirements

- Perl 5
- Image::ExifTool Perl module (or standalone `exiftool`)
- Standard Perl modules: `File::Find`, `Getopt::Long`, `Time::Piece`

### Installing Dependencies

**Debian/Ubuntu:**
```bash
sudo apt-get install libimage-exiftool-perl
```

**macOS (with Homebrew):**
```bash
brew install exiftool
```

**CPAN:**
```bash
cpan Image::ExifTool
```

## Usage

```bash
./date-sanitize.pl [OPTIONS] [PATH ...]
```

### Basic Examples

Process a single image file:
```bash
./date-sanitize.pl photo.jpg
```

Process all supported files in current directory:
```bash
./date-sanitize.pl
```

Process directory recursively:
```bash
./date-sanitize.pl -r /path/to/photos
```

Process specific file types:
```bash
./date-sanitize.pl -e jpg,png /path/to/photos
```

## Options

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Recursively process subdirectories |
| `-e, --ext LIST` | Comma-separated list of file extensions (default: jpg,jpeg,heic,tif,tiff,png,mp4,mov,m4v) |
| `--tz ZONE` | Fallback timezone for timestamps without timezone info |
| `--min-year YYYY` | Ignore date candidates before this year (default: 2000) |
| `--debug` | Print detailed information about each date candidate |
| `--deep` | Include embedded/maker-note streams in analysis |
| `-h, --help` | Display help message |

## How It Works

1. **Extract**: Reads all date/time fields from file metadata using ExifTool, plus a date parsed from the filename when it matches a known pattern (WhatsApp `IMG/VID-YYYYMMDD-WA*`, Android `YYYYMMDD_HHMMSS`, Pixel `PXL_YYYYMMDD_HHMMSS...`). Date-only filenames are taken as 12:00 noon local time.
2. **Filter**: Excludes GPS dates, system dates (MacOS), pseudo-tags, and invalid timestamps (midnight values, dates outside year range). Filesystem dates are not regular candidates: the file modification time is used only as a **last resort** when nothing else qualifies (it is usually just the copy time), and access/inode/create dates are ignored entirely.
3. **Select**: Chooses the earliest valid date among all candidates
4. **Update**:
   - Images: sets `EXIF:DateTimeOriginal` and `EXIF:OffsetTimeOriginal`
   - Videos: sets `QuickTime:CreateDate` and `QuickTime:ModifyDate` (stored as UTC, per spec) and `Keys:CreationDate` (Apple's timezone-aware tag, preferred by iOS Photos)

The script preserves subsecond precision and timezone information when available. QuickTime dates are read and written assuming UTC storage (as the spec requires); cameras that incorrectly store local time in `CreateDate` will read shifted by the UTC offset — check a sample with `--debug` before large batches.

## Output Status

The script outputs one line per file with the following statuses:

- `APPLIED`: Successfully updated the date field(s)
- `UNCHANGED`: Current date already matches the earliest valid date
- `NOCHANGE`: A write was attempted but ExifTool made no changes to the file
- `SKIPPED`: No valid date candidates found or all dates outside acceptable range
- `ERROR`: Failed to read or write the file

Each line includes:
- Current date value
- New date value (if changed)
- Source tag of the selected date
- Number of date candidates parsed

## Examples

Process photos with specific timezone:
```bash
./date-sanitize.pl --tz America/New_York *.jpg
```

Debug mode to see all date candidates:
```bash
./date-sanitize.pl --debug photo.jpg
```

Process only files from 2020 onwards:
```bash
./date-sanitize.pl --min-year 2020 -r ./photos
```

Deep scan including embedded metadata:
```bash
./date-sanitize.pl --deep --recursive ./photos
```

## Backups

The script modifies files **in place** and does not create backups. Keep a copy of your originals before running it on an irreplaceable collection.

## Exit Codes

- `0`: Success (all files processed without errors)
- `1`: Invalid command-line options
- `2`: One or more files failed to process

## Supported File Formats

**Images:**
- JPEG (`.jpg`, `.jpeg`)
- HEIC (`.heic`)
- TIFF (`.tif`, `.tiff`)
- PNG (`.png`)

**Videos:**
- MP4 (`.mp4`, `.m4v`)
- QuickTime (`.mov`)

Additional formats can be specified using the `-e` option.

## License

See LICENSE file for details.

