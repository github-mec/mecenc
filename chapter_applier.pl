#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use File::Copy;

my ($input_file, $output_file) = @ARGV;
die "Input file should be a chapter file\n" unless $input_file =~ m/\.txt$/;
die "Output file should be a mp4 file\n" unless $output_file =~ m/^(.+)\.mp4[av]?$/;

my $chapter_file = "$1.chapters.txt";
die "Temp chapter file already exists.\n" if -e $chapter_file;

copy $input_file, $chapter_file;
`mp4chaps -r "$output_file"`;
`mp4chaps -i "$output_file"`;
unlink $chapter_file;
