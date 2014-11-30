#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use POSIX qw/:math_h/;

die "Scene file doesn't exist." unless -f 'scene.txt';
die "Filtered scene file doesn't exist." unless -f 'scene_filtered.txt';
die "dump dir doesn't exist." unless -d 'dump';
die "Index file already exists." if -e 'index.html';

open my $scene_fh, '<', 'scene.txt' or die;
my @all_sccenes = <$scene_fh>;
close $scene_fh;

open my $scene_filtered_fh, '<', 'scene_filtered.txt' or die;
my %scene_type_hash;
for my $line (<$scene_filtered_fh>) {
    my ($index, $type) = (split '\s+', $line)[0, 5];
    $scene_type_hash{$index} = lc $type;
}
close $scene_filtered_fh;

opendir my $dh, 'dump' or die;
my @dirnames = sort grep(!/^\./, readdir($dh));
closedir $dh;

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
for my $i (0..$#dirnames) {
    my $dirname = $dirnames[$i];
    if (defined $scene_type_hash{$i}) {
        $current_type = $scene_type_hash{$i};
    }

    my ($scene_index, $range_type, $start, $end, $changed) =
        split '\s+', $all_sccenes[$i];
    push @output, sprintf(
        '<h3>%02d: (%s) %s - %s - %s (%s)</h3>',
        $scene_index, $range_type,
        frameDiffStr($changed, $start), $changed, frameDiffStr($end, $changed),
        frameToTime($changed));

    push @output, '<div>';
    my $template = '<img width="224px" height="126px" class="%s" src="dump/%s/%d.png">';
    push @output, 
        sprintf($template, $previous_type, $dirname, 1) .
        sprintf($template, $previous_type, $dirname, 2) .
        sprintf($template, $current_type, $dirname, 3) .
        sprintf($template, $current_type, $dirname, 4);
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
        $result .= floor($sec / 3600) . ':';
        $sec = $sec % 3600;
    }
    $result .= sprintf('%02d:%02d.%02d', floor($sec / 60), $sec % 60, floor(($time - $sec) * 100));
    return $result;
}

sub frameDiffStr {
    my ($x, $y) = @_;
    my $value = POSIX::floor(abs($x - $y) * 2 + 0.1);
    return ($value % 2 == 0)
        ? sprintf('%d', $value / 2) : sprintf('%.1f', $value / 2.0);
}
