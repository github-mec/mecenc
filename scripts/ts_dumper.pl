#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use File::Basename;
use File::Spec;
use Getopt::Long;

my %options;
GetOptions(\%options, qw/aggressive_analysis/)
    or die 'Failed to parse options on ts_dumper.';

my $script_dirname = File::Basename::dirname(File::Spec->rel2abs($0));
$script_dirname =~ s/ /\\ /g;

my $input_filename = shift @ARGV;
die "No such file. [$input_filename]" unless -f $input_filename;
die "Input file should be ts or m2ts or mp4."
    unless $input_filename =~ m%([^/]+)\.(ts|m2ts|mp4|ts\.filepart)$%;
my $basename = $1;
my $movie_filename = "in.mp4v";
my $audio_filename = "in.wav";
my $raw_silence_filename = "raw_silence.txt";
my $silence_filename = "silence.txt";
die "A file already exists. [$movie_filename]" if -e $movie_filename;
die "A file already exists. [$audio_filename]" if -e $audio_filename;
die "A file already exists. [$raw_silence_filename]"
    if -e $raw_silence_filename;
die "A file already exists. [$silence_filename]" if -e $silence_filename;

my $clean_command = '';
my $ffmpeg_input = '';
if ($input_filename =~ m/\.mp4$/) {
    $ffmpeg_input = '"' . $input_filename . '"';
} else {
    $clean_command =
        qq#$script_dirname/ts_cleaner/ts_cleaner "$input_filename" - |#;
    $ffmpeg_input = '-';
}

my $aggressive_analysis = $options{aggressive_analysis};

system(
    qq|$clean_command ffmpeg -i $ffmpeg_input| .
    qq| -an -vcodec copy -f mp4 "$movie_filename"| .
    qq| -vn -acodec pcm_s24le -f wav "$audio_filename"|) and die;
my $silence_detector_options =
    $aggressive_analysis ? '--aggressive_analysis' : '';
system(
    qq|$script_dirname/silence_detector/silence_detector| .
    qq| $silence_detector_options "$audio_filename"| .
    qq| > "$raw_silence_filename"|) and die;
if ($aggressive_analysis) {
    system(qq|cp "$raw_silence_filename" "$silence_filename"|) and die;
} else {
    system(qq|$script_dirname/simple_silence_filter.pl|) and die;
}
