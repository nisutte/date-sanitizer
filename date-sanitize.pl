#!/usr/bin/env perl
use strict;
use warnings;

BEGIN {
    eval { require Image::ExifTool; Image::ExifTool->import(':Public'); 1 } and return;
    my $exe = `which exiftool 2>/dev/null`;
    chomp $exe;
    if ($exe && open my $fh, '<', $exe) {
        while (my $line = <$fh>) {
            if ($line =~ /^use lib '([^']+)';/) {
                unshift @INC, $1;
                last;
            }
        }
        close $fh;
        eval { require Image::ExifTool; Image::ExifTool->import(':Public'); 1 } and return;
    }
    die "Image::ExifTool Perl module not found. Install libimage-exiftool-perl or ensure exiftool is available.\n";
}

use File::Find qw(find);
use Getopt::Long qw(GetOptionsFromArray);
use Time::Piece;

my %CFG = (
    recursive   => 0,
    debug       => 0,
    deep        => 0,
    min_year    => 2000,
    fallback_tz => $ENV{TZ} // '',
    exts        => [qw(jpg jpeg heic tif tiff png mp4 mov m4v)],
);

sub trim { my ($s) = @_; $s //= ''; $s =~ s/^\s+//; $s =~ s/\s+$//; $s }
sub parse_value { my ($v) = @_; map { trim($_) } split /\|/, $v // '', 4 }
sub colon_offset { my ($o) = @_; $o =~ /^[+-]\d{4}$/ ? substr($o,0,3).':'.substr($o,3,2) : '' }
sub usage {
    print <<'EOF';
Usage: date-sanitize.pl [OPTIONS] [PATH ...]
  -r, --recursive         Recurse directories
  -e, --ext LIST          Comma extensions (default: jpg,jpeg,heic,tif,tiff,png,mp4,mov,m4v)
      --tz ZONE           Fallback timezone for naive values
      --min-year YYYY     Ignore candidates before year (default: 2000)
      --debug             Print every accepted candidate
      --deep              Include embedded/maker-note streams
  -h, --help              Show this help
EOF
}

sub status {
    my ($status, $file, $from, $to, $source, $count) = @_;
    $file   = (split m{/+}, $file)[-1];
    $from   = length $from   ? $from   : 'NONE';
    $to     = length $to     ? $to     : 'NONE';
    $source = length $source ? $source : 'NONE';
    my $line = sprintf('%s  %s  from=%s  to=%s  source=%s', $status, $file, $from, $to, $source);
    $line .= sprintf('  parsed=%d', $count) if defined $count;
    $status eq 'ERROR' ? print STDERR "$line\n" : print "$line\n";
    return $status eq 'ERROR' ? 1 : 0;
}

sub build_reader {
    my $et = Image::ExifTool->new;
    $et->Options(
        Duplicates        => 1,
        Unknown           => 1,
        IgnoreMinorErrors => 1,
        RequestAll        => 3,
        QuickTimeUTC      => 1,
        DateFormat        => '%s|%Y:%m:%d %H:%M:%S|%z|%f',
        ExtractEmbedded   => $CFG{deep} ? 3 : 0,
    );
    return $et;
}

sub build_writer {
    my $et = Image::ExifTool->new;
    $et->Options(QuickTimeUTC => 1);
    return $et;
}

sub collect_files {
    my @targets = @_ ? @_ : ('.');
    my %allow = map { $_ => 1 } @{ $CFG{exts} };
    my @files;
    my $wanted = sub {
        return unless -f $_;
        my ($ext) = lc(($File::Find::name =~ /\.([^.]+)$/)[0] // '');
        push @files, $File::Find::name if $allow{$ext};
    };
    for my $path (@targets) {
        if (-f $path) {
            my ($ext) = lc(($path =~ /\.([^.]+)$/)[0] // '');
            push @files, $path if $allow{$ext};
            next;
        }
        if (-d $path) {
            if ($CFG{recursive}) {
                find({ wanted => $wanted, no_chdir => 1 }, $path);
            } else {
                opendir(my $dh, $path) or do { warn "WARN  $path  reason=unreadable\n"; next };
                while (my $entry = readdir $dh) {
                    next if $entry =~ /^\.\.?$/;
                    my $full = "$path/$entry";
                    next unless -f $full;
                    my ($ext) = lc(($entry =~ /\.([^.]+)$/)[0] // '');
                    push @files, $full if $allow{$ext};
                }
                closedir $dh;
            }
            next;
        }
        warn "WARN  $path  reason=skipped (not a file)\n";
    }
    return @files;
}

sub epoch_for_year {
    my $year = shift;
    local $ENV{TZ} = $CFG{fallback_tz} if length $CFG{fallback_tz};
    return Time::Piece->strptime("$year-01-01 00:00:00", '%Y-%m-%d %H:%M:%S')->epoch;
}

sub process_file {
    my ($reader, $writer, $file, $min_epoch, $max_epoch) = @_;

    local $ENV{TZ} = $CFG{fallback_tz} if length $CFG{fallback_tz};
    $reader->ExtractInfo($file, undef, undef, 'Time:All') or return status('ERROR', $file);

    my $is_video = ($reader->GetValue('MIMEType') // '') =~ m{^video/};

    my $cur_raw = $is_video
        ? ($reader->GetValue('CreateDate', 'PrintConv') // $reader->GetValue('CreationDate', 'PrintConv'))
        : $reader->GetValue('DateTimeOriginal', 'PrintConv');
    my ($cur_epoch, $cur_display, undef, $cur_subsec) = parse_value($cur_raw);
    my @tags = $reader->GetTagList('Time');
    my (@names, @epochs, @displays, @offsets, @subsecs);

    for my $tag (@tags) {
        my $group = $reader->GetGroup($tag, 1) // '';
        next if $group =~ /^GPS/ || $group eq 'MacOS' || $group =~ /^ICC/;
        for my $val ($reader->GetValue($tag, 'PrintConv')) {
            next unless defined $val;
            my ($epoch, $display, $offset, $subsec) = parse_value($val);
            next unless $epoch =~ /^\d{9,}$/;
            next if $display =~ /00:00:00$/;
            next if $tag eq 'GPSDateTime';
            next if $display =~ /^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}Z?$/ && $group eq 'Composite' && $tag eq 'GPSDateTime';
            push @names, sprintf('%s:%s', $group || 'Unknown', $tag);
            push @epochs,   $epoch;
            push @displays, $display;
            push @offsets,  $offset;
            push @subsecs,  $subsec;
            print STDERR "DEBUG $group $display\n" if $CFG{debug};
        }
    }

    my $parsed = @epochs;
    return status('SKIPPED', $file, $cur_display, undef, undef, 0) unless $parsed;

    my ($best_idx, $best_epoch) = (-1, 0);
    for my $i (0 .. $#epochs) {
        my $epoch = $epochs[$i];
        next if $epoch < $min_epoch || $epoch > $max_epoch;
        if ($best_idx == -1 || $epoch < $best_epoch) {
            ($best_idx, $best_epoch) = ($i, $epoch);
        }
    }
    return status('SKIPPED', $file, $cur_display, undef, undef, $parsed) if $best_idx == -1;

    my $winner_tag     = $names[$best_idx];
    my $winner_display = $displays[$best_idx];
    my $winner_offset  = $offsets[$best_idx];
    my $winner_subsec  = $subsecs[$best_idx];

    my $write_wall = $winner_display;
    my $subsec     = length $winner_subsec ? $winner_subsec : $cur_subsec;
    my $offset     = length $winner_offset  ? $winner_offset  : (length $CFG{fallback_tz} ? localtime($best_epoch)->strftime('%z') : '');

    my $target = $write_wall;
    $target .= ".$subsec" if length $subsec && !$is_video;
    $target .= $offset     if length $offset;

    if (defined $cur_epoch && $cur_epoch =~ /^\d+$/ && $cur_epoch == $best_epoch) {
        if (!length $winner_subsec || $winner_subsec eq ($cur_subsec // '')) {
            return status('UNCHANGED', $file, $cur_display, $target, $winner_tag, $parsed);
        }
    }

    $writer->SetNewValue();
    if ($is_video) {
        # QuickTimeUTC on the writer converts these to UTC using the given
        # offset (or $TZ when no offset is known); Keys:CreationDate keeps
        # the offset, which is what iOS Photos prefers.
        my $value = $write_wall . colon_offset($offset);
        $writer->SetNewValue($_, $value)
            for qw(QuickTime:CreateDate QuickTime:ModifyDate Keys:CreationDate);
    } else {
        $writer->SetNewValue('EXIF:DateTimeOriginal', $write_wall);
        $writer->SetNewValue('EXIF:OffsetTimeOriginal', colon_offset($offset)) if length $offset;
    }

    my $rc = $writer->WriteInfo($file);
    return status('ERROR', $file, $cur_display, undef, $winner_tag, $parsed) unless $rc;
    return status('NOCHANGE', $file, $cur_display, $target, $winner_tag, $parsed) if $rc == 2;
    return status('APPLIED', $file, $cur_display, $target, $winner_tag, $parsed);
}

sub main {
    my @argv = @_ ? @_ : ('.');
    GetOptionsFromArray(
        \@argv,
        'r|recursive'        => \$CFG{recursive},
        'e|ext=s'            => sub { $CFG{exts} = [ map { lc trim($_) } split /,/, $_[1] ] },
        'tz=s'               => \$CFG{fallback_tz},
        'min-year=i'         => \$CFG{min_year},
        'debug'              => \$CFG{debug},
        'deep'               => \$CFG{deep},
        'h|help'             => sub { usage(); exit 0 },
    ) or do { usage(); return 1 };

    my @files = collect_files(@argv);
    unless (@files) {
        print "No matching files.\n";
        return 0;
    }

    my $min_epoch = epoch_for_year($CFG{min_year});
    my $max_epoch = time + 86400;

    my $reader = build_reader();
    my $writer = build_writer();

    my $failures = 0;
    for my $file (@files) {
        $failures += process_file($reader, $writer, $file, $min_epoch, $max_epoch);
    }

    return $failures ? 2 : 0;
}

exit main(@ARGV);

