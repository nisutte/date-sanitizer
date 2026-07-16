# Date Sanitizer

Finds the earliest valid date across all metadata of an image or video and makes it the authoritative one — embedded tags *and* filesystem timestamps. Useful for fixing timestamps from misconfigured cameras, consolidating conflicting date fields, and making media show the correct date after importing to an iPhone (e.g. via the Apple Devices app on Windows).

## Requirements

Perl 5 with `Image::ExifTool`:

```bash
sudo apt-get install libimage-exiftool-perl   # Debian/Ubuntu
brew install exiftool                         # macOS
cpan Image::ExifTool                          # anywhere
```

## Usage

```bash
./date-sanitize.pl [OPTIONS] [PATH ...]
```

```bash
./date-sanitize.pl photo.jpg              # single file
./date-sanitize.pl -r /path/to/media      # directory, recursive
./date-sanitize.pl --tz Europe/Zurich -r ./media
```

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Recurse into subdirectories |
| `-e, --ext LIST` | Extensions to process (default: jpg,jpeg,heic,tif,tiff,png,mp4,mov,m4v) |
| `--tz ZONE` | Fallback timezone for timestamps without timezone info |
| `--min-year YYYY` | Ignore date candidates before this year (default: 2000) |
| `--debug` | Print every date candidate |
| `--deep` | Include embedded/maker-note streams |
| `-h, --help` | Show help |

## How It Works

1. **Collect candidates**: all embedded date tags, plus a date parsed from the filename (WhatsApp `IMG/VID-YYYYMMDD-WA*`, Android `YYYYMMDD_HHMMSS`, Pixel `PXL_...`; date-only names count as 12:00 noon). GPS/system/pseudo dates and midnight values are excluded; the file's mtime is used only as a last resort.
2. **Select** the earliest candidate within the allowed year range.
3. **Write**:
   - Images: `EXIF:DateTimeOriginal` + `OffsetTimeOriginal`
   - Videos: `QuickTime:CreateDate`/`ModifyDate` (UTC, per spec) + Apple's timezone-aware `Keys:CreationDate`, plus the filesystem modification time (and creation time on Windows) — Apple's sync pipeline trusts filesystem timestamps over embedded metadata for videos. If only the mtime is wrong, it's fixed without rewriting the file.

Note: QuickTime dates are read assuming UTC storage (per spec); cameras that store local time instead will read shifted — check a sample with `--debug` before large batches.

## Output

One line per file: `STATUS file from=... to=... source=... parsed=N`

- `APPLIED` — dates updated
- `UNCHANGED` — embedded date (and, for videos, mtime) already correct
- `NOCHANGE` — write attempted but ExifTool made no changes
- `SKIPPED` — no valid date candidate found
- `ERROR` — read/write failure (exit code 2)

⚠️ Files are modified **in place**, no backups are created — keep a copy of irreplaceable originals.

## License

See LICENSE file.
