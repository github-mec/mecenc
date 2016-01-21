#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use constant {
    RECORDER_MAX_HEAD_MARGIN_FRAMES => 6.7 * 30000 / 1001.0,
    MAX_CM_FRAMES => (3 * 60 + 3) * 30000 / 1001.0,
    RANGE_5_SEC => [146.4, 152.6],
    RANGE_10_SEC => [296.2, 302.6],
    RANGE_15_SEC => [446.4, 452.6],
    RANGE_30_SEC => [896.4, 901.6],
    RANGE_60_SEC => [1795.6, 1800.7],
    RANGE_90_SEC => [2694.7, 2699.9],
    RANGE_120_SEC => [3593.8, 3599.0],
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

my $logo_filter_data = loadFilterData('logo.txt', 1);
my $sponsor_filter_data = loadFilterData('sponsor.txt', 2);
my %cm_set = ();

LINE: for (my $i = 0; $i < $#lines; ++$i) {
    # CM of the previous program may exist.
    if (getExactFrame($lines[$i + 1]) < RECORDER_MAX_HEAD_MARGIN_FRAMES) {
        $cm_set{$lines[$i]} = 1;
        next LINE;
    }
    for (my $j = $i + 1; $j <= $#lines; ++$j) {
        if (isBodyByData($j - 1, $logo_filter_data, @lines) ||
            isBodyByData($j - 1, $sponsor_filter_data, @lines)) {
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
@result = filterByData($logo_filter_data, @result);
@result = filterByData($sponsor_filter_data, @result);
@result = filterByMixedBoundary(@result);


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
        RANGE_15_SEC,
        RANGE_30_SEC,
        RANGE_60_SEC,
    );
    my $is_logo_detection_enabled = -f 'logo.txt';
    if ($is_logo_detection_enabled) {
        push @ranges, RANGE_5_SEC;
        push @ranges, RANGE_10_SEC;
        push @ranges, RANGE_90_SEC;
        push @ranges, RANGE_120_SEC;
    }

    my $frame_num = getDurationInFrameNum($a, $b);
    for my $range (@ranges) {
        if (inRange($range, $frame_num)) {
            return 1;
        }
    }

    return 0;
}

# Filter CM on the tail.
# This script marks the last chunk as CM. If the last CM has silent range, the
# head of the last CM will be marked as BODY.
# This filter marks such chunk as CM.
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
        # Don't handle a short input movie.
        return @lines;
    }
    # A long input movie should have two or more CMs at the tail.
    if (getType($lines[-2]) eq 'CM') {
        # There is no pieces of CM.
        return @lines;
    }

    my $body_index = $#lines - 2;
    for (; $body_index >= 0; --$body_index) {
        my $line = $lines[$body_index];
        if (getType($line) eq 'CM') {
            ++$body_index;
            last;
        }
    }

    if ($body_index == 0) {
        # An input movie should have body.
        return @lines;
    }
    my $body_duration = getTimeFromFrameNum(
        $last_exact_frame - getExactFrame($lines[$body_index]));
    if ($body_duration > 121) {
        # Handle 120sec or shorter CM only.
        return @lines;
    }

    for my $line (@lines[$body_index .. $#lines - 1]) {
        setType($line, 'CM');
    }

    return @lines;
}

sub isBodyByData {
    my ($index, $filter_data, @lines) = @_;
    if ($index + 1 > $#lines) {
        return 0;
    }

    my $start_frame = getUpperFrame($lines[$index]);
    my $end_frame = getLowerFrame($lines[$index + 1]);
    my $start = POSIX::ceil(getTimeFromFrameNum($start_frame));
    my $end = POSIX::floor(getTimeFromFrameNum($end_frame));
    for (my $i = $start; $i <= $end; ++$i) {
        if (exists $filter_data->{$i}) {
            return 1;
        }
    }
    return 0;
}

sub filterByData {
    my ($filter_data, @lines) = @_;
    for my $index (0..$#lines) {
        if (getType($lines[$index]) ne 'BODY' &&
            isBodyByData($index, $filter_data, @lines)) {
            setType($lines[$index], 'BODY');
        }
    }
    return @lines;
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

# TODO: Handle a CM which consists of multiple chunks.
sub filterByMixedBoundary {
    my @lines = @_;

    my @ranges = (
        RANGE_5_SEC,
        RANGE_10_SEC,
        RANGE_15_SEC);

    for (my $i = 1; $i <= $#lines - 1; ++$i) {
        my $previous_line = $lines[$i - 1];
        my $line = $lines[$i];
        my $next_line = $lines[$i + 1];

        if (getType($line) eq 'BODY') {
            next;
        }

        # Skip if unexpected duration.
        # TODO: Handle a CM which is splitted into multiple chunks.
        my $duration = getExactFrame($next_line) - getExactFrame($line);
        my $in_range = 0;
        for my $range (@ranges) {
            $in_range |= inRange($range, $duration);
        }
        if (!$in_range) {
            next;
        }

        if (getType($previous_line) eq 'CM' &&
            getType($next_line) eq 'BODY' &&
            isExactMixedBoundary($line)) {
            setType($lines[$i], 'BODY');
            next;
        }

        if (getType($previous_line) eq 'BODY' &&
            getType($next_line) eq 'CM' &&
            isExactMixedBoundary($next_line)) {
            setType($lines[$i], 'BODY');
            next;
        }
    }
    return @lines;
}

sub isExactMixedBoundary {
    my $line = shift;
    if (!isExact($line)) {
        return 0;
    }
    my $frame = getExactFrame($line);
    return abs($frame - int($frame)) > 0.4;
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

sub inRange {
    my ($range, $value) = @_;
    return $range->[0] <= $value && $value <= $range->[1];
}

sub loadFilterData {
    my ($filename, $image_duration_sec) = @_;
    if (!-e $filename) {
        return undef;
    }
    open my $fh, '<', $filename or die 'Failed to open $filename.';
    my %filter_data = ();
    for my $data (<$fh>) {
        my ($index, $is_body) = split ' ', $data;
        $index = int($index) * $image_duration_sec;
        if ($is_body eq 'True') {
            $filter_data{$index} = 1;
        }
    }
    close $fh;
    return \%filter_data;
}
