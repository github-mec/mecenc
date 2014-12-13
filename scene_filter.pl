#!/usr/bin/perl

use strict;
use warnings;
use utf8;

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
# First segment may be a body.
push @candidates, $lines[0];
LINE: for (my $i = 0; $i <= $#lines - 1; ++$i) {
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
#@candidates = do { my %c; grep {!$c{$_}++} @candidates[1..$#candidates] };  # uniq. remove first dummy line.
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
    my $diff_min = $b_min - $a_max;
    my $diff_max = $b_max - $a_min;

    if ($a_is_exact && $b_is_exact) {
        # temmporary hack for noitamina.
        if (147.4 <= $diff_min && $diff_min <= 151.6 && $a_min < 3300) {
            return 1;
        }

        # min == max
        if (146.4 <= $diff_min && $diff_min <= 152.6) {
            return 1;
        }
        if (446.4 <= $diff_min && $diff_min <= 452.6) {
            return 1;
        }
        if (896.4 <= $diff_min && $diff_min <= 901.6) {
            return 1;
        }
        if (1795.6 <= $diff_min && $diff_min <= 1800.7) {
            return 1;
        }
        if (2694.7 <= $diff_min && $diff_min <= 2699.9) {
            return 1;
        }
        return 0;
    }

    return 0;
}

sub dumpLine {
    my $a = shift;
    my $min = getLower($a);
    my $max = getUpper($a);
    my $exact = getExact($a);

    if (defined $exact && $a =~ m/exact/) {
        $exact = POSIX::floor($exact * 10 + 0.1) / 10.0;
        return (1, $exact, $exact);
    } else {
        return (0, int($min), int($max));
    }
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
        my $start_frame = getUpper($lines[$i - 1]);
        my $end_frame = getLower($lines[$i]);
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
                getLower($lines[$i]) - getUpper($lines[$cm_start_index]));
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

sub getLower {
    my $line = shift;
    return (split('\s+', $line))[2];
}

sub getUpper {
    my $line = shift;
    return (split('\s+', $line))[3];
}

sub getExact {
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
