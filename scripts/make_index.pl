#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use POSIX qw/:math_h/;

die "scene.txt doesn't exist." unless -f 'scene.txt';
die "dump/ directory doesn't exist." unless -d 'dump';
die "index.html already exists." if -e 'index.html';

open my $scene_fh, '<', 'scene.txt' or die;
my @all_scenes = <$scene_fh>;
close $scene_fh;
my %scene_type_hash;
for my $line (@all_scenes) {
    my ($index, $type) = (split '\s+', $line)[0, 5];
    $scene_type_hash{$index} = lc $type;
}

my @output = (
    '<html>',
    '<head>',
    '<style type="text/css">',
    'img {padding: 4px; margin: 0px;}',
    '.cm {background-color: yellow;}',
    '.body {background-color: red;}',
    '</style>',
    '</head>',
    '<body>');
my $previous_type = 'cm';
my $current_type = 'cm';
for my $i (0..$#all_scenes) {
    if (defined $scene_type_hash{$i}) {
        $current_type = $scene_type_hash{$i};
    }

    my ($scene_index, $range_type, $start, $end, $changed) =
        split '\s+', $all_scenes[$i];
    push @output, sprintf(
        '<h3>%02d: (%s) %s - %s - %s (%s)</h3>',
        $scene_index, $range_type,
        frameDiffStr($changed, $start), $changed, frameDiffStr($end, $changed),
        frameToTime($changed));

    push @output, '<div>';
    my $template =
        '<img width="224px" height="126px" class="%s" src="dump/%03d/%d.jpg">';
    push @output, 
        sprintf($template, $previous_type, $i, 1) .
        sprintf($template, $previous_type, $i, 2) .
        sprintf($template, $current_type, $i, 3) .
        sprintf($template, $current_type, $i, 4);
    push @output, '</div>';
    $previous_type = $current_type;
}
push @output, '</body></html>';

open my $out_fh, '>', 'index.html' or die;
print $out_fh "$_\n" for @output;
close $out_fh;

exit(0);


sub frameToTime {
    my $frame = shift;
    my $time = $frame * 1001.0 / 30000.0;
    my $sec = floor($time);
    my $result = '';
    if ($sec >= 3600) {
        my $hour = floor($sec / 3600);
        $result .= sprintf('%d:', $hour);
        $time -= $hour * 3600;
        $sec -= $hour * 3600;
    }
    $result .= sprintf(
        '%02d:%02d.%02d',
        floor($sec / 60), $sec % 60, floor(($time - $sec) * 100));

    return $result;
}

sub frameDiffStr {
    my ($x, $y) = @_;
    my $value = POSIX::floor(abs($x - $y) * 2 + 0.1);
    return ($value % 2 == 0)
        ? sprintf('%d', $value / 2) : sprintf('%.1f', $value / 2.0);
}
