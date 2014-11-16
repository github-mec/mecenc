#!/usr/bin/perl

use strict;
use warnings;
use utf8;

my $index = 1;
for my $filename (@ARGV) {
    die unless -f $filename;
    my $value = (`ffmpeg -i "$filename" 2>&1 1| grep "Duration: "`)[0];
    $value =~ m/Duration: ([\d:]+)/;
    print sprintf("%2d: %s\n", $index, $1);
    ++$index;
}
