#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use List::Util;

# TODO: Use information about CM length. (5, 15, 30, 60 or 90 sec)

open my $ifh, '<', 'scene.txt' or die "Failed to open scene.txt.";
my @lines = <$ifh>;
close $ifh;

@lines = grep {$_ =~ m/exact.+CM$/} @lines;
if ($#lines == -1) {
    print STDERR "There is no CM.\n";
    exit(0);
}

my @values = ();
for my $line (@lines) {
    my $border_time = (split '\s+', $line)[4];
    my $value = FrameToTime($border_time) - int(FrameToTime($border_time));
    push @values, $value;
}

my ($start, $duration) = DetectSceneChangeRange(@values);
open my $ofh, '>', 'scene_offset.txt'
    or die "ailed to create scene_offset.txt.";
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
    my @filtered_values = FilterByRange($start, $start + $margin, \@values);
    for my $value (@filtered_values) {
        $value += 1 if $value < $start;
    }
    @filtered_values = sort @filtered_values;
    my $count = scalar @filtered_values;
    my $median_value = ($count % 2 == 0)
        ? ($filtered_values[$count / 2 - 1] + $filtered_values[$count / 2]) / 2
        : $filtered_values[($count - 1) / 2];
    $median_value -= 1 if $median_value >= 1;
    return ($median_value - $margin / 2.0, $margin);
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
