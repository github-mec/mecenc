#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;
use POSIX;

my %options;
GetOptions(\%options, qw/no_scale no_decimate interlaced/) or die;

my $basename = 'in';
my $video_filename = 'in.mp4v';
die "No such file. [$video_filename]" unless -f $video_filename;
my $audio_filename = 'in.wav';
die "No such file. [$audio_filename]" unless -f $audio_filename;
my $scene_filename = 'scene_filtered.txt';
die "No such file. [$scene_filename]" unless -f $scene_filename;
my $output_filename = 'result.mp4';
die "The output file is already exists. [$output_filename]" if -e $output_filename;
my $video_result_filename = "result.mp4v";
die "The vide result file is already exists. [$video_result_filename]" if -e $video_result_filename;
my $audio_result_filename = "result.mp4a";
die "The audio_result file is already exists. [$audio_result_filename]" if -e $audio_result_filename;
my $concat_filename = "concat.txt";
die "The concat file is already exists. [$concat_filename]" if -e $concat_filename;

open my $scene_fh, '<', $scene_filename or die "Failed to open scene file. [$scene_filename]";
my @scene_list = <$scene_fh>;
close $scene_fh;

my @frame_list = ();
{
    my $start_frame = undef;
    for my $line (@scene_list) {
        chomp $line;
        my ($frame, $type) = (split '\s+', $line)[4, 5];
        die "Invalid scene: $line" unless defined $type;
        if ($type eq 'BODY') {
            $start_frame //= $frame;
        } elsif ($type eq 'CM') {
            if (defined $start_frame) {
                push @frame_list, [$start_frame, $frame];
                $start_frame = undef;
            }
        }
    }
}

my $video_command = qq|ffmpeg -i "$video_filename" |;
my $index = 1;
my @video_temp_filenames;
for my $frame (@frame_list) {
    my $start = POSIX::ceil($frame->[0]);
    my $end = POSIX::floor($frame->[1]);
    my $temp_filename = sprintf("%s%02d.mp4v", $basename, $index);
    push @video_temp_filenames, $temp_filename;
    die "A temp file is already exists. [$temp_filename]" if -e $temp_filename;
    $video_command .= qq|-an -vcodec libx264 -crf 18 -preset slow -tune animation -deblock 0:0 -qmin 10 -f mp4 |;
    my $filter_v = qq|-filter:v trim=start_frame=$start:end_frame=$end|;
    if ($options{interlaced}) {
        $video_command .= qq|-flags +ilme+ildct |;
    } elsif ($options{no_decimate}){
        $filter_v .= ',yadif';
    } else {
        my $original_height = getOriginalHeight();
        my $y0 = POSIX::floor($original_height / 4.0);
        my $y1 = POSIX::ceil($original_height * 3.0 / 4.0);
        $filter_v .= qq|,fieldmatch=combmatch=none:y0=$y0:y1=$y1,decimate=scthresh=100,yadif|
    }
    if (!$options{no_scale}) {
        $filter_v .= qq|,scale=width=1280:height=720|;
        $video_command .= qq|-sws_flags lanczos+accurate_rnd |;
    }
    $filter_v .= qq|,setpts=PTS-STARTPTS |;
    $video_command .= qq| $filter_v "$temp_filename" |;
    $index++;
}
`$video_command`;

open my $concat_fh, '>', $concat_filename or die "Failed to open concat file. [$concat_filename]";
for (@video_temp_filenames) {
    my $name = $_;
    $name =~ s/ /\\ /g;
    print $concat_fh qq|file $name\n| 
}
close $concat_fh;
`ffmpeg -f concat -i "$concat_filename" -c copy -f mp4 "$video_result_filename"`;

$index = 1;
my @audio_commands = ();
my $sox_command = 'sox ';
my $video_delay = getVideoDelay($video_filename);
my $audio_delay = 2624.0 / 48000.0;  # 2624 samples delay by neroAacEnc.
for my $frame (@frame_list) {
    my $start = $frame->[0] * 1001.0 / 30000.0 + $video_delay + $audio_delay;
    my $duration = dumpDuration(shift @video_temp_filenames);
    my $temp_filename = sprintf("%s%02d.wav", $basename, $index);
    `ffmpeg -i "$audio_filename" -ss $start -t $duration "$temp_filename"`;
    $sox_command .= qq|"$temp_filename" |;
    # Audio delay is not required for the other frames.
    $audio_delay = 0;
    $index++;
}
$sox_command .= qq#-t wav - | neroAacEnc -q 0.55 -ignorelength -if - -of "$audio_result_filename"#;
`$sox_command`;
`mp4chaps -r "$audio_result_filename"`;

`ffmpeg -i "$video_result_filename" -i "$audio_result_filename" -c copy -movflags faststart "$output_filename"`;

exit;

sub getVideoTempFilename {
    my $a = shift;
    sprintf("%s%02d.mp4v", $basename, $index)
}

sub getVideoDelay {
    my $a = shift;
    my $line = `ffmpeg -i "$a" 2>&1 1| grep "Duration: "`;
    $line =~ m/start: (\d+)\.(\d+)/;
    my $sec = int($1) + int($2) * 0.000001;
    return $sec;
}

sub getOriginalHeight {
    my $a = shift;
    my $line = `ffmpeg -i "$a" 2>&1 1| grep "Stream #" | grep ": Video: "`;
    my ($width, $height) = $line =~ m/(\d+)x(\d+)/;
    return $height;
}

sub dumpDuration {
    my $a = shift;
    my $line = `ffmpeg -i "$a" 2>&1 1| grep "Duration: "`;
    $line =~ m/Duration: (\d+):(\d+):(\d+)\.(\d+)/;
    my $sec = int($1) * 3600 + int($2) * 60 + int($3) + int($4) / 100;
    ($sec + 0.5) =~ m/^(\d+)/;
    return int($1);
}
