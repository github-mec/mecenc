#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use constant {
    RECORDER_MAX_HEAD_MARGIN_FRAMES => 6.5 * 30000 / 1001.0,
};

use List::Util qw/min max/;
use POSIX;


my $input_filename = 'scene.txt';
die "No such file. [$input_filename]" unless -f $input_filename;
my $output_filename = "scene_filtered.txt";
die "A file already exists. [$output_filename]" if -e $output_filename;

open my $input_fh, '<', $input_filename or die "Failed to open a file. [$input_filename]";
my @lines;
push @lines, <$input_fh>;
close $input_fh;

my @candidates = ();
my %cm_set = ();
push @candidates, $lines[0];
LINE: for (my $i = 0; $i <= $#lines - 1; ++$i) {
    # First segment may be a body.
    if (getExactFrame($lines[$i]) < RECORDER_MAX_HEAD_MARGIN_FRAMES) {
        push @candidates, $lines[$i];
    }
    for (my $j = $i + 1; $j <= $#lines; ++$j) {
        if (checkDiff($lines[$i], $lines[$j])) {
            push @candidates, $lines[$i];
            push @candidates, $lines[$j];
            $cm_set{$lines[$i]} = 1;
            $i = $j - 1;
            next LINE;
        }
    }
}
push @candidates, $lines[$#lines];
@candidates = do { my %c; grep {!$c{$_}++} @candidates };  # uniq

my @result = ();
for my $value (@candidates) {
    if ($cm_set{$value} || $value eq $candidates[$#candidates]) {
        chomp $value;
        push @result, "$value CM";
    } else {
        chomp $value;
        push @result, "$value BODY";
    }
}

@result = filterHeadCmGroup(@result);
@result = filterLogoDetection(@result);
@result = filterShortCmGroup(@result);
@result = filterAggregateBody(@result);

open my $output_fh, '>', $output_filename or die "Failed to open file. [$output_filename]";
print $output_fh "$_\n" for @result;
close $output_fh;

exit;


sub checkDiff {
    my ($a, $b) = @_;
    my ($a_is_exact, $a_min, $a_max) = dumpLine($a);
    my ($b_is_exact, $b_min, $b_max) = dumpLine($b);
    if (!$a_is_exact || !$b_is_exact) {
        return 0;
    }
    my $diff_min = $b_min - $a_max;
    my $diff_max = $b_max - $a_min;

    my @ranges = (
        [446.4, 452.6],  # 15 sec
        [896.4, 901.6],  # 30 sec
        [1795.6, 1800.7],  # 60 sec
    );
    my $is_logo_detection_enabled = -f 'logo.txt';
    if ($is_logo_detection_enabled) {
        push @ranges, [146.4, 152.6];  # 5 sec
        push @ranges, [2694.7, 2699.9];  # 90 sec
    }

    for my $range (@ranges) {
        if ($range->[0] <= $diff_min && $diff_min <= $range->[1]) {
            return 1;
        }
    }

    return 0;
}

sub dumpLine {
    my $a = shift;
    my $min = getLowerFrame($a);
    my $max = getUpperFrame($a);
    my $exact = getExactFrame($a);

    if (defined $exact && $a =~ m/exact/) {
        $exact = POSIX::floor($exact * 10 + 0.1) / 10.0;
        return (1, $exact, $exact);
    } else {
        return (0, int($min), int($max));
    }
}

sub filterHeadCmGroup {
    my @lines = @_;

    my $last_cm_index = -1;
    for (my $i = 1; $i <= $#lines; ++$i) {
        my $line = $lines[$i];
        if (!isExact($line)) {
            next;
        }
        if (getExactFrame($line) > RECORDER_MAX_HEAD_MARGIN_FRAMES) {
            last;
        }
        $last_cm_index = $i - 1;
    }

    for my $i (0..$last_cm_index) {
        setType($lines[$i], 'CM');
    }

    return @lines;
}

sub filterTailCmGroup {
}

sub filterLogoDetection {
    my @lines = @_;
    my $filename = 'logo.txt';
    if (!-e $filename) {
        return @lines;
    }

    open my $fh, '<', $filename or die 'Failed to open $filename.';
    my @logo_data = ();
    for my $data (<$fh>) {
        my $has_logo = (split ' ', $data)[1];
        push @logo_data, ($has_logo eq 'True');
    }
    close $fh;

    for (my $i = 1; $i <= $#lines; ++$i) {
        my $start_frame = getUpperFrame($lines[$i - 1]);
        my $end_frame = getLowerFrame($lines[$i]);
        my $start = POSIX::ceil(getTimeFromFrameNum($start_frame));
        my $end = POSIX::floor(getTimeFromFrameNum($end_frame));
        my $is_body = 0;
        for (my $j = $start; $j <= $end; ++$j) {
            if ($logo_data[$j]) {
                $is_body = 1;
                last;
            }
        }
        if ($is_body) {
            setType($lines[$i - 1], 'BODY');
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
                my $remove_num = $i - $cm_start_index;
                splice @lines, $cm_start_index, $remove_num;
                $i -= $remove_num;
            }
        }
        $cm_start_index = undef;
    }
    return @lines;
}

sub filterAggregateBody {
    my @lines = @_;
    my $previous_type = '';
    for (my $i = 0; $i < $#lines; ++$i)  {
        my $type = getType($lines[$i]);
        if ($previous_type eq 'BODY' and $type eq 'BODY') {
            splice @lines, $i, 1;
            --$i;
        }
        $previous_type = $type;
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
