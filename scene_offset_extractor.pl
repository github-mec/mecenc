#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use List::Util;

# TODO: Use information about CM length. (5, 15, 30 or 60sec)

open my $ifh, '<', 'scene_filtered.txt' or die "Failed to open scene_filtered.txt.";
my @lines = <$ifh>;
close $ifh;

@lines = grep {$_ =~ m/exact.+CM$/} @lines;
if ($#lines == -1) {
    # TODO: Handle this condiiton.
    die "There is no CM.";
}

my @values = ();
for my $line (@lines) {
    my $border_time = (split '\s+', $line)[4];
    my $value = FrameToTime($border_time) - int(FrameToTime($border_time));
    push @values, $value;
}

my ($start, $duration) = DetectSceneChangeRange(@values);
open my $ofh, '>', 'scene_offset.txt' or die "ailed to create scene_offset.txt.";
print $ofh sprintf("%.3f %.3f", $start, $duration);
close $ofh;

exit(0);


sub FrameToTime {
    my $value = shift;
    return $value * 1001.0 / 30000.0;
}

sub DetectSceneChangeRange {
    my @values = sort @_;

    my $margin = FrameToTime(3.8);
    my $max_count = 0;
    my $index = 0;
    for (my $i = 0; $i <= $#values; ++$i) {
        my $value = $values[$i];
        my $count = scalar(FilterByRange($value, $value + $margin, \@values));
        if ($count > $max_count) {
            $max_count = $count;
            $index = $i;
        }
    }

    my $start = $values[$index];
    my $duration = undef;
    my @filtered_values = FilterByRange($start, $start + $margin, \@values);
    if ($start + $margin >= 1.0) {
        my @lower_values = FilterByRange(0, $margin, \@filtered_values);
        if ($#lower_values != -1) {
            $duration = List::Util::max(@lower_values) + 1 - $start;
        }
    }
    $duration //= List::Util::max(@filtered_values) - $start;

    $start -= ($margin - $duration) / 2;
    if ($start < 0) {
        $start += 1;
    }
    return ($start, $margin);
}

sub FilterByRange {
    my ($start, $end, $values) = @_;
    my @result = ();
    for my $value (@$values) {
        if (($start <= $value && $value < $end) ||
            $value < $end - 1) {
            push @result, $value;
        }
    }
    return @result;
}
