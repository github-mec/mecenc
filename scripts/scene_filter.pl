#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use constant {
    RECORDER_MAX_HEAD_MARGIN_FRAMES => 6.7 * 30000 / 1001.0,
    MAX_CM_FRAMES => (3 * 60 + 3) * 30000 / 1001.0,
};

use List::Util qw/min max/;
use POSIX;


my $input_filename = 'raw_scene.txt';
die "No such file. [$input_filename]" unless -f $input_filename;
my $output_filename = "scene.txt";
die "A file already exists. [$output_filename]" if -e $output_filename;

open my $input_fh, '<', $input_filename
    or die "Failed to open a file. [$input_filename]";
my @lines;
push @lines, map {chomp; $_} <$input_fh>;
close $input_fh;

my $logo_data = loadLogoData();
my %cm_set = ();

LINE: for (my $i = 0; $i < $#lines; ++$i) {
    # CM of the previous program may exist.
    if (getExactFrame($lines[$i + 1]) < RECORDER_MAX_HEAD_MARGIN_FRAMES) {
        $cm_set{$lines[$i]} = 1;
        next LINE;
    }
    for (my $j = $i + 1; $j <= $#lines; ++$j) {
        if (hasLogoInRange($j - 1, $logo_data, @lines)) {
            next LINE;
        }
        if (checkDiff($lines[$i], $lines[$j])) {
            for my $k ($i .. $j - 1) {
                $cm_set{$lines[$k]} = 1;
            }
            $i = $j - 1;
            next LINE;
        }
        if (getDurationInFrameNum($lines[$i], $lines[$j]) > MAX_CM_FRAMES) {
            next LINE;
        }
    }
}

my @result = ();
for my $value (@lines) {
    if ($cm_set{$value} || $value eq $lines[$#lines]) {
        push @result, "$value CM";
    } else {
        push @result, "$value BODY";
    }
}

@result = filterTailCmGroup(@result);
@result = filterShortCmGroup(@result);

open my $output_fh, '>', $output_filename
    or die "Failed to open file. [$output_filename]";
print $output_fh "$_\n" for @result;
close $output_fh;

exit;


sub getDurationInFrameNum {
    my ($a, $b) = @_;
    return getExactFrame($b) - getExactFrame($a);
}

sub checkDiff {
    my ($a, $b) = @_;
    if (!isExact($a) || !isExact($b)) {
        return 0;
    }

    my @ranges = (
        [446.4, 452.6],  # 15 sec
        [896.4, 901.6],  # 30 sec
        [1795.6, 1800.7],  # 60 sec
    );
    my $is_logo_detection_enabled = -f 'logo.txt';
    if ($is_logo_detection_enabled) {
        push @ranges, [146.4, 152.6];  # 5 sec
        push @ranges, [296.2, 302.6];  # 10 sec
        push @ranges, [2694.7, 2699.9];  # 90 sec
    }

    my $frame_num = getDurationInFrameNum($a, $b);
    for my $range (@ranges) {
        if ($range->[0] <= $frame_num && $frame_num <= $range->[1]) {
            return 1;
        }
    }

    return 0;
}

# TODO: Employ more robust way.
sub filterTailCmGroup {
    my @lines = @_;

    my $last_line = $lines[-1];
    if (getType($last_line) ne 'CM' or $#lines < 1) {
        # Unexpected situation.
        return @lines;
    }
    my $last_exact_frame = getExactFrame($last_line);
    if (getTimeFromFrameNum($last_exact_frame) < 7.5 * 60) {
        # Don't handle short movie.
        return @lines;
    }
    if (getType($lines[-2]) eq 'CM') {
        # There is no pieces of CM.
        return @lines;
    }

    my $body_index = $#lines - 1;
    for (my $body_index = $#lines; $body_index >= 0; --$body_index) {
        my $line = $lines[$body_index];
        if (getType($line) eq 'CM') {
            ++$body_index;
            last;
        }
    }

    my $body_duration = getTimeFromFrameNum(
        $last_exact_frame - getExactFrame($lines[$body_index]));
    # Handle 90sec or shorter CM.
    if ($body_duration > 91) {
        return @lines;
    }

    for my $line (@lines[$body_index .. $#lines - 1]) {
        setType($line, 'CM');
    }

    return @lines;
}

sub hasLogoInRange {
    my ($index, $logo_data, @lines) = @_;
    if ($index + 1 > $#lines) {
        return 0;
    }

    my $start_frame = getUpperFrame($lines[$index]);
    my $end_frame = getLowerFrame($lines[$index + 1]);
    my $start = POSIX::ceil(getTimeFromFrameNum($start_frame));
    my $end = POSIX::floor(getTimeFromFrameNum($end_frame));
    for (my $i = $start; $i <= $end; ++$i) {
        if ($logo_data->[$i]) {
            return 1;
        }
    }
}

sub filterShortCmGroup {
    my @lines = @_;
    my $first_body_index = undef;
    for (my $i = 0; $i <= $#lines; ++$i) {
        if (getType($lines[$i]) eq 'BODY') {
            $first_body_index = $i;
            last;
        }
    }

    my $cm_start_index = undef;
    for (my $i = $first_body_index + 1; $i <= $#lines - 1; ++$i) {
        my $type = getType($lines[$i]);
        if ($type eq 'CM') {
            $cm_start_index //= $i;
            next;
        }
        if ($type ne 'BODY') {
            die 'Unexpectd chunk type: $type';
        }
        if ($cm_start_index) {
            my $duration = getTimeFromFrameNum(
                getLowerFrame($lines[$i])
                - getUpperFrame($lines[$cm_start_index]));
            if ($duration < 25) {
                for my $line (@lines[$cm_start_index .. $i]) {
                    setType($line, 'BODY');
                }
            }
        }
        $cm_start_index = undef;
    }
    return @lines;
}

sub isExact {
    my $line = shift;
    return (split('\s+', $line))[1] eq 'exact';
}

sub getLowerFrame {
    my $line = shift;
    return (split('\s+', $line))[2];
}

sub getUpperFrame {
    my $line = shift;
    return (split('\s+', $line))[3];
}

sub getExactFrame {
    my $line = shift;
    return (split('\s+', $line))[4];
}

sub getType {
    my $line = shift;
    return (split('\s+', $line))[5];
}

sub setType {
    my ($line, $type) = @_[0, 1];
    my @values = split('\s+', $line);
    $values[5] = $type;
    $_[0] = join(' ', @values);
}

sub getTimeFromFrameNum {
    my $frame_num = shift;
    return $frame_num * 1001 / 30000.0;
}

sub loadLogoData {
    my $filename = 'logo.txt';
    if (!-e $filename) {
        return undef;
    }
    open my $fh, '<', $filename or die 'Failed to open $filename.';
    my @logo_data = ();
    for my $data (<$fh>) {
        my $has_logo = (split ' ', $data)[1];
        push @logo_data, ($has_logo eq 'True');
    }
    close $fh;
    return \@logo_data;
}
