#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use constant {
    LOCK_DIR => '/tmp/encode_movie.lock',
};

use Cwd;
use File::Basename;
use File::Spec;
use Getopt::Long;

$SIG{TERM} = \&errorHandler;
$SIG{INT} = \&errorHandler;
$SIG{HUP} = \&errorHandler;
$SIG{__DIE__} = \&errorHandlerWithoutExit;

my %options;
my $base_dirname = $ENV{HOME} . '/enc';
$options{tempdir} = "$base_dirname/encoding";
$options{destdir} = "$base_dirname/encoded";
$options{logdir} = "$base_dirname/log";
GetOptions(\%options, qw/help no_scale no_decimate no_encode no_clean no_lock public_log interlaced tempdir=s destdir=s logdir=s scenefile=s scenelistfile=s logo=s/) or die help();

if ($options{help}) {
    die help();
}

our $HAS_LOCK = 0;
our $CLEAN_DIR = undef;
getLock() unless $options{no_lock};

my $script_dirname = File::Basename::dirname(File::Spec->rel2abs($0));
$script_dirname =~ s/ /\\ /g;

my $temp_dirname = File::Spec->rel2abs($options{tempdir});
my $dest_dirname = File::Spec->rel2abs($options{destdir});
my $original_dirname = Cwd::getcwd();

my @input_filenames = map {File::Spec->rel2abs($_)} @ARGV;
for my $input_filename (@input_filenames) {
    die "No such file. [$input_filename]" unless -f $input_filename;
    die "Input file should be ts or mp4." unless $input_filename =~ m%([^/]+)\.(ts|mp4|ts\.filepart)$%;
}

my @scene_filenames = ();
if (defined $options{scenefile}) {
    die "Don't specify multiple input files with -scenefile option." if $#input_filenames != 0;
    push @scene_filenames, $options{scenefile};
} 
if (defined $options{scenelistfile}) {
    die "Don't specify input files with -scenelist option." if $#input_filenames != -1;
    open my $scenelist_ofh, '<', $options{scenelistfile} or die;
    my @list = map {chomp; $_} grep({m/\S/} <$scenelist_ofh>);
    while ($#list >= 1) {
        push @input_filenames, shift(@list);
        push @scene_filenames, shift(@list);
    }
    close $scenelist_ofh;
}

die "Input argument num check failure." unless ($#scene_filenames == -1 || $#input_filenames == $#scene_filenames);

my @output_scenefilenames = ();
for (my $i = 0; $i <= $#input_filenames; ++$i) {
    my $input_filename = $input_filenames[$i];
    my $scene_filename = ($i <= $#scene_filenames)
        ? File::Spec->rel2abs($scene_filenames[$i])
        : undef;
    $input_filename =~ m%([^/]+)\.(ts|mp4|ts\.filepart)$%;
    my $basename = $1;
    my $working_dirname = "$temp_dirname/enc_$basename";
    $CLEAN_DIR = $options{no_clean} ? undef : $working_dirname;

    if (!mkdir($working_dirname) || !chdir($working_dirname)) {
        die "Failed to create a working directory. [$working_dirname]";
    }

    my $output_filename = "$dest_dirname/$basename.mp4";
    my $log_dirname = File::Spec->rel2abs(($options{logdir}) . sprintf('/%s %s', getTimestampString(), $basename));

    print "output: $output_filename\n";
    print "log: $log_dirname\n";
    if (-e $output_filename || -e $log_dirname) {
        die "Output file and/or log directory already exists.";
    }

    execute(qq|$script_dirname/ts_dumper.pl "$input_filename"|);
    if (defined $scene_filename) {
        execute(qq|cp "$scene_filename" "scene_filtered.txt"|);
    } else {
        if ($options{logo}) {
            my $logo = $options{logo};
            execute(qq|$script_dirname/scene_change_detector.py --logo=$logo|);
            execute(qq|$script_dirname/logo_detector.py --logo=$logo|);
        } else {
            execute(qq|$script_dirname/scene_change_detector.py|);
        }
        execute(qq|$script_dirname/scene_filter.pl|);
        execute(qq|$script_dirname/scene_offset_extractor.pl|);

        if (-f 'scene_offset.txt') {
            open my $offset_ifh, '<', 'scene_offset.txt' or die "Failed to open scene_offset.txt";
            my ($start, $duration) = split '\s+', <$offset_ifh>;
            close $offset_ifh;
            execute(qq|mv "scene.txt" "scene.txt.orig"|);
            execute(qq|mv "scene_filtered.txt" "scene_filtered.txt.orig"|);
            execute(qq|$script_dirname/scene_change_detector.py --scene_time_filter=$start,$duration --no_dump=True|);
            execute(qq|$script_dirname/scene_filter.pl|);
        }

        execute(qq|$script_dirname/make_index.pl|);
        execute(qq|$script_dirname/salvage.pl "$log_dirname"|);
        if ($options{public_log}) {
            execute(qq|chmod -R 777 "$log_dirname"|);
        }
    }
    if ($options{no_encode}) {
        push @output_scenefilenames, "$log_dirname/scene_filtered.txt";
    } else {
        my $option = '';
        $option .= $options{no_scale} ? '-no_scale ' : '';
        $option .= $options{no_decimate} ? '-no_decimate ' : '';
        $option .= $options{interlaced} ? '-interlaced ' : '';
        execute(qq|$script_dirname/encoder.pl $option|);

        my @video_part_files = sort(grep {m/in\d+\.mp4v/} `ls`);
        chomp for @video_part_files;
        if ($#video_part_files > 0) {
            my $joined_video_part_files = join(' ', map({sprintf '"%s"', $_} @video_part_files));
            execute(qq|$script_dirname/chapter_dumper.pl $joined_video_part_files "chapter.txt"|);
            execute(qq|$script_dirname/chapter_applier.pl "chapter.txt" "result.mp4"|);
        }
        execute(qq|mv "result.mp4" "$output_filename"|);
    }
    cleanTempDirectory();

    if (!chdir($original_dirname)) {
        die "Failed to create a working directory.";
    }
}

if ($options{no_encode}) {
    die "The number of output scene files should be equal to inputs."
        unless $#input_filenames == $#output_scenefilenames;
    my $scenelist_filename = sprintf(
        '%s/%s_scenelist.txt', File::Spec->rel2abs($options{logdir}), getTimestampString());
    open my $scenelist_ofh, '>', $scenelist_filename or die "Failed to create a file. [$scenelist_filename]";
    for (my $i = 0; $i <= $#input_filenames; ++$i) {
        print $scenelist_ofh $input_filenames[$i], "\n";
        print $scenelist_ofh $output_scenefilenames[$i], "\n";
    }
    close $scenelist_ofh;
}

unlock() unless $options{no_lock};

exit(0);


sub help {
    print <<'HELP';
encode.pl [options] [ts_file_1 ts_file_2 ...]
encode.pl --scenelistfile scenelistfile

--tempdir: Temp directory
--destdir: Output directory
--logdir:  Log directory, which contains data for CM cut feature.
--no_encode:  Generate log data and scenelist file (for --scenelistfile) only.
--no_lock:  Run scripts without lock.
--no_clean:  Do not remove a temp directory.
--no_scale:  Do not scale movies.
--no_decimate:  Do not decimate frames and keep original fps.
--interlaced:  Keep interlace.
--scenefile:  Use pre-generated scene file (scene_filtered.txt) for CM cut.
--scenelistfile: Scenelist file for batch encoding.
                 Use pre-generated scene files and TS files listed in this file.
--public_log: Make the permission of log data public.
HELP
}

sub getLock {
    our $HAS_LOCK;
    print "trying to get a lock...\n";
    while (!mkdir(LOCK_DIR)) {
        sleep 60 + int(rand 30);
    }
    $HAS_LOCK = 1;
    print "got a lock.\n";
}

sub unlock {
    our $HAS_LOCK;
    if ($HAS_LOCK) {
        rmdir LOCK_DIR;
        $HAS_LOCK = 0;
        print "lock is released.\n";
    }
}

sub errorHandler {
    errorHandlerWithoutExit();
    exit(1);
}

sub errorHandlerWithoutExit {
    cleanTempDirectory();
    unlock();
}

sub execute {
    my $command = shift;
    my $ret = system($command);
    if ($ret) {
        print "Failed: $command\n";
        errorHandler();
        exit($ret);
    }
}

sub cleanTempDirectory {
    # Don't use execute(), which may call this method.
    our $CLEAN_DIR;
    if (defined $CLEAN_DIR) {
        if ($CLEAN_DIR =~ m|/enc_|) {
            system(qq|rm -rf "$CLEAN_DIR" > /dev/null 2>&1|);
        }
    }
}

sub getTimestampString {
    my ($min, $hour, $mday, $mon, $year) = (localtime(time))[1, 2, 3, 4, 5];
    return sprintf('%04d-%02d-%02d_%02d%02d', $year + 1900, $mon + 1, $mday, $hour, $min);
}
