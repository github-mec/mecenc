#!/usr/bin/perl

use strict;
use warnings;
use utf8;

die 'raw_silence.txt is not found.' unless -f 'raw_silence.txt';
die 'silence.txt already exists.' if -e 'silence.txt';

open my $ifh, '<', 'raw_silence.txt' or die;
my @lines = map {chomp; $_} <$ifh>;
close $ifh;

my $first_line = shift @lines;
my @result = ($first_line);
my $total_time = (split '\s+', $first_line)[2];

LOOP: for my $x (@lines) {
    my ($start, $end) = split '\s+', $x;
    if ($start < 30) {
        push @result, $x;
        next LOOP;
    }
    my $duration = $end - $start;
    if ($duration >= 3.0) {
        push @result, sprintf("%.3f %.3f", $start, $start + $duration / 2.5);
        push @result, sprintf("%.3f %.3f", $end - $duration / 2.5, $end);
        next LOOP;
    }
    for my $y (@lines) {
        if (checkDistance($x, $y)) {
            push @result, $x;
            next LOOP;
        }
    }
}

open my $ofh, '>', 'silence.txt' or die;
print $ofh "$_\n" for @result;
close $ofh;

exit;

sub checkDistance {
    my ($line_a, $line_b) = @_;

    my ($a_min, $a_max) = split '\s+', $line_a;
    my ($b_min, $b_max) = split '\s+', $line_b;
    if ($a_min > $b_min) {
        return checkDistance($line_b, $line_a);
    }
    my $min_range = $b_min - $a_max;
    my $max_range = $b_max - $a_min;

    my @ranges = (5, 15, 30, 60);
    for my $range (@ranges) {
        if ($min_range < $range && $range < $max_range) {
            return 1;
        }
    }

    return 0;
}
