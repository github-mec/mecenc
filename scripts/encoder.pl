#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;
use POSIX;

my %options;
GetOptions(\%options, qw/no_scale keep_fps interlaced x265 crf=f/) or die;

my $basename = 'in';
my $video_filename = 'in.mp4v';
die "No such file. [$video_filename]" unless -f $video_filename;
my $audio_filename = 'in.wav';
die "No such file. [$audio_filename]" unless -f $audio_filename;
my $scene_filename = 'scene.txt';
die "No such file. [$scene_filename]" unless -f $scene_filename;
my $output_filename = 'result.mp4';
die "The output file is already exists. [$output_filename]"
    if -e $output_filename;
my $video_result_filename = $options{x265} ? "result.265" : "result.mp4v";
die "The vide result file is already exists. [$video_result_filename]"
    if -e $video_result_filename;
my $audio_result_filename = "result.mp4a";
die "The audio_result file is already exists. [$audio_result_filename]"
    if -e $audio_result_filename;
my $concat_filename = "concat.txt";
die "The concat file is already exists. [$concat_filename]"
    if -e $concat_filename;
my $chapter_filename = 'chapter.txt';
die "The chapter file is already exists. [$chapter_filename]"
    if -e $chapter_filename;
if ($options{interlaced}) {
    die "Cannot use --keep_fps and --interlaced options at the same time."
        if $options{keep_fps};
    die "Cannot use --no_scale and --interlaced options at the same time."
        if $options{no_scale};
}

open my $scene_fh, '<', $scene_filename
    or die "Failed to open scene file. [$scene_filename]";
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

my $pix_fmt_option = getPixFmtOption(\%options);
my $video_command = qq|ffmpeg -i "$video_filename" |;
my $index = 1;
my @video_temp_filenames;
for my $frame (@frame_list) {
    my $start = POSIX::ceil($frame->[0]);
    my $end = POSIX::floor($frame->[1]);
    my $temp_filename = '';
    my $video_option = '';
    if ($options{x265}) {
        my $crf = $options{crf} // 19;
        $video_option =
            "-vcodec libx265 -preset medium -f hevc $pix_fmt_option " .
            "-x265-params " .
                "crf=$crf:colorprim=bt709:transfer=bt709:colormatrix=bt709 ";
        $temp_filename = sprintf("%s%02d.265", $basename, $index);
    } else {
        my $crf = $options{crf} // 18;
        $video_option =
            "-vcodec libx264 -crf $crf -preset slow -tune animation " .
            "-f mp4 $pix_fmt_option -deblock 0:0 -qmin 10 " .
            "-x264-params colorprim=bt709:transfer=bt709:colormatrix=bt709 ";
        $temp_filename = sprintf("%s%02d.mp4v", $basename, $index);
    }
    die "A temp file is already exists. [$temp_filename]" if -e $temp_filename;
    push @video_temp_filenames, $temp_filename;
    $video_command .= qq|-an $video_option |;
    my $filter_v = qq|-filter:v trim=start_frame=$start:end_frame=$end|;
    if ($options{interlaced}) {
        $video_command .= qq|-flags +ilme+ildct |;
    } elsif ($options{keep_fps}) {
        $filter_v .= ',yadif';
    } else {
        my $original_height = getOriginalHeight();
        my $y0 = POSIX::floor($original_height / 4.0);
        my $y1 = POSIX::ceil($original_height * 3.0 / 4.0);
        $filter_v .=
            ",fieldmatch=combmatch=none:y0=$y0:y1=$y1" .
            ",decimate=scthresh=100,yadif"
    }
    if (!$options{no_scale}) {
        $filter_v .= qq|,scale=width=1280:height=720|;
        $video_command .= qq|-sws_flags lanczos+accurate_rnd |;
    }
    $filter_v .= qq|,lutyuv=y=clipval,setpts=PTS-STARTPTS|;
    $video_command .= qq|$filter_v "$temp_filename" |;
    $index++;
}
`$video_command`;

open my $concat_fh, '>', $concat_filename
    or die "Failed to open concat file. [$concat_filename]";
for (@video_temp_filenames) {
    my $name = $_;
    $name =~ s/ /\\ /g;
    print $concat_fh qq|file $name\n| 
}
close $concat_fh;

my $concat_command = qq|ffmpeg -f concat -i "$concat_filename" -c copy |;
if ($options{x265}) {
    $concat_command .= qq|-f hevc "$video_result_filename" |;
} else {
    $concat_command .= qq|-f mp4 "$video_result_filename" |
}
`$concat_command`;

my $fps = 24000.0 / 1001;
my $fps_str = '24000/1001';
if ($options{interlaced} || $options{keep_fps}) {
    $fps = 30000.0 / 1001;
    $fps_str = '30000/1001';
}

$index = 1;
my @audio_commands = ();
my $sox_command = 'sox ';
my $video_delay = getVideoDelay($video_filename);
my @durations = ();
for my $frame (@frame_list) {
    my $start = $frame->[0] * 1001.0 / 30000.0 + $video_delay;
    my $duration = dumpDuration(shift(@video_temp_filenames), $fps);
    push @durations, $duration;
    my $temp_filename = sprintf("%s%02d.wav", $basename, $index);
    `ffmpeg -i "$audio_filename" -ss $start -t $duration "$temp_filename"`;
    $sox_command .= qq|"$temp_filename" |;
    $index++;
}
writeChapterFile($chapter_filename, \@durations);

my $audio_delay = 2624.0 / 48000.0;  # 2624 samples delay by neroAacEnc.
$sox_command .=
    qq#-t wav - | ffmpeg -i - -ss $audio_delay -c copy -f wav pipe: # .
    qq#|neroAacEnc -q 0.55 -ignorelength -if - -of "$audio_result_filename" #;
`$sox_command`;

if ($options{x265}) {
    my $muxer_command =
        qq|muxer --file-format mp4 --optimize-pd | .
        qq|--chapter "$chapter_filename" | .
        qq|-i "$video_result_filename"?fps=$fps_str | .
        qq|-i "$audio_result_filename" | .
        qq|-o "$output_filename" |;
    `$muxer_command`;
} else {
    # L-SMASH bug? Failed to mux. Use ffmpeg instead.
    # Commit: 7124bbeccb552021f2e6b31cbd923eeff7322cb5
    my $muxer_command =
        qq|ffmpeg -i "$video_result_filename" -i "$audio_result_filename" | .
        qq|-c copy -movflags faststart "$output_filename" |;
    `$muxer_command`;
}

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
    my ($width, $height) = $line =~ m/(\d{2,})x(\d{2,})/;
    return $height;
}

sub dumpDuration {
    my ($filename, $fps) = @_;
    my $line = '';
    if ($filename =~ m/\.265$/) {
        my $temp_filename = $filename . '.tmp.mp4';
        `ffmpeg -i "$filename" -c copy -f mp4 -y "$temp_filename"`;
        $line = `ffmpeg -i "$temp_filename" 2>&1 1| grep "Duration: "`;
        `rm $temp_filename`;
    } else {
        $line = `ffmpeg -i "$filename" 2>&1 1| grep "Duration: "`;
    }

    $line =~ m/Duration: (\d+):(\d+):(\d+)\.(\d+)/;
    my $sec = int($1) * 3600 + int($2) * 60 + int($3) + int($4) / 100.0;
    my $frame_num = $sec * $fps;
    ($frame_num + 0.5) =~ m/^(\d+)/;

    return int($1) / $fps;
}

sub writeChapterFile {
    my ($filename, $durations) = @_;

    open my $fh, '>', $filename
        or die "Failed to open a file. [$filename]";
    my $total_time = 0;
    my $index = 0;
    for my $duration (@$durations) {
        my $total_usec = POSIX::ceil($total_time * 1e6);
        my $total_sec = POSIX::floor($total_usec / 1e6);
        my $hour = POSIX::floor($total_sec / 3600);
        my $sec = $total_sec % 60;
        my $min = POSIX::floor(($total_sec - $hour * 3600 - $sec) / 60);
        my $usec = $total_usec % 1000000;
        print $fh sprintf("CHAPTER%02d=%02d:%02d:%02d.%06d\n",
                          $index, $hour, $min, $sec, $usec);
        print $fh sprintf("CHAPTER%02dNAME=\n", $index);

        $total_time += $duration;
        ++$index;
    }
    close $fh;
}

sub getPixFmtOption {
    my $options = shift;
    my @lines = ();
    if ($options{x265}) {
        @lines = `x265 --help 2>&1 1| grep 16bpp`;
    } else {
        @lines = `x264 --help 2>&1 1| grep "Output bit depth: 10"`;
    }
    if (@lines) {
        return '-pix_fmt yuv420p10le';
    } else {
        return '';
    }
}
