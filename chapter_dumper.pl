#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use List::Util qw/min max/;

my $output_filename = pop @ARGV;
die "Output file already exists. [$output_filename]" if -f $output_filename;
die "Output file should be txt." unless $output_filename =~ m|\.txt$|;

my @video_filenames = @ARGV;
for my $filename (@video_filenames) {
    die "No such file. [$filename]" unless -f $filename;
    die "Video file should be mp4v." unless $filename =~ m|\.mp4v$|;
}

my @times = ();
for my $filename (@video_filenames) {
    my @output = `ffmpeg -i "$filename" 2>&1`;
    die unless (grep {m/Duration:/} @output)[0] =~ m/Duration: (\d+):(\d+):(\d+)\.(\d+),/;
    my $time = $1 * 3600 + $2 * 60 + $3 + $4 * 0.01;
    die unless (grep {m/fps/} @output)[0] =~ m/\ ([\d\.]+) fps/;
    my $fps = $1;
    if ($fps eq '23.98') {
        push @times, int($time * 24000.0 / 1001.0 + 0.5) * 1001.0 / 24000.0;
    } elsif ($fps eq '29.97') {
        push @times, int($time * 30000.0 / 1001.0 + 0.5) * 1001.0 / 30000.0;
    } else {
        die "Unknown fps";
    }
}

open my $chapter_fh, '>', $output_filename or die "Failed to open a file. [$output_filename]";
my $total_time = 0;
my $index = 0;
for my $time (@times) {
    my $total_sec = int($total_time);
    my $hour = int($total_sec / 3600);
    my $sec = $total_sec % 60;
    my $min = int(($total_sec - $hour * 3600 - $sec) / 60);
    my $usec = ($total_time - $total_sec) * 1e6;
    print $chapter_fh sprintf("CHAPTER%02d=%02d:%02d:%02d.%06d\n", $index, $hour, $min, $sec, $usec);
    print $chapter_fh sprintf("CHAPTER%02dNAME=\n", $index);

    $total_time += $time;
    ++$index;
}
close $chapter_fh;

