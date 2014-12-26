#!/usr/bin/perl

use strict;
use warnings;
use constant {
    TARGET_FILENAMES => [
        'index.html',
        'logo.txt',
        'raw_silence.txt',
        'silence.txt',
        'raw_scene.txt',
        'raw_scene.txt.orig',
        'scene.txt',
        'scene.txt.orig',
        'scene_offset.txt',
    ],
    TARGET_DIRNAMES => [
    ],
};

use File::Basename;
use File::Path;
use POSIX;

my $raw_scene_filename = 'raw_scene.txt';
my $output_dirname = shift @ARGV;

die "No such file. [$raw_scene_filename]" unless -f $raw_scene_filename;
die "Please specify the output directory." unless $output_dirname;
die "Output directory already exists. [$output_dirname]" if -e $output_dirname;

File::Path::mkpath($output_dirname)
    or die qq|Failed to create the output directory "$output_dirname"|;

for my $filename (@{TARGET_FILENAMES()}) {
    `cp "$filename" "$output_dirname/$filename"`;
}
for my $dirname (@{TARGET_DIRNAMES()}) {
    `cp -R "$dirname" "$output_dirname/$dirname"`;
}

open my $fh, '<', $raw_scene_filename
    or die qq|Failed to load "$raw_scene_filename".|;
my @lines = <$fh>;
close $fh;

my $base_dump_dirname = "$output_dirname/dump";
for my $line (@lines) {
    my ($body_index, $start, $end, $target) = (split '\s+', $line)[0, 2, 3, 4];

    my $from_dirname = sprintf("dump/%03d", $body_index);
    my $to_dirname = "$output_dirname/$from_dirname";
    File::Path::mkpath($to_dirname);

    ($start, $end, $target) =
        map {POSIX::floor($_ * 2 + 0.1)} ($start, $end, $target);
    my $in1 = sprintf("%04d.png", 1);
    my $in2 = sprintf("%04d.png", $target - $start);
    my $in3 = sprintf("%04d.png", $target - $start + 1);
    my $in4 = sprintf("%04d.png", $end - $start + 2);

    `convert -resize 224x126 "$from_dirname/$in1" "$to_dirname/1.jpg"`;
    `convert -resize 224x126 "$from_dirname/$in2" "$to_dirname/2.jpg"`;
    `convert -resize 224x126 "$from_dirname/$in3" "$to_dirname/3.jpg"`;
    `convert -resize 224x126 "$from_dirname/$in4" "$to_dirname/4.jpg"`;
    `cp "$from_dirname/dump.mp4v" "$to_dirname"`;
}
