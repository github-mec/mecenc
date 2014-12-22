# How to use:

## Simple
    ./mecenc.pl input_file_1.ts [input_file_2.ts ...]
* CM detection.
* Encode by x264.
* Convert the frame ratio from 30fps to 24fps and deinterlace.
* Shrink the movie to 1280 x 720 since almost all animations are created in this resolution.
* Don't use broadcaster watermark detection for CM detection.
* Working / output / log directory is in ~/enc/.

## Encode by x265
    ./mecenc.pl --encoder x265 input_file.ts

## Enable broadcaster watermark detection
    ./mecenc.pl --logo logo_name input_file.ts
* logo\_name.png and logo\_name.txt should be in a logo directory.

## CM detection only (don't encode)
    ./mecenc.pl --no_encode input_file.ts

## Encode with detected CM information (single files)
    ./mecenc.pl --scenefile /path/to/scene_filtered.txt input_file.ts

## Encode with detected CM information (multiple files)
    ./mecenc.pl --scenelistfile /path/to/yyyy-mm-dd_hhmm_scenelist.txt

## Encode with interlaced movie
    ./mecenc.pl --interlaced input_file.ts

## Encode for a 30 fps animation
    ./mecenc.pl --no_decimate input_file.ts

## Don't shrink the movie
    ./mecenc.pl --no_scale input_file.ts

## Specify directories
    ./mecenc.pl --tempdir tempdir --destdir destdir --logdir logdir input_file.ts

## Don't clean the working directory
    ./mecenc.pl --no_clean input_file.ts

## Don't lock other mecenc
    ./mecenc.pl --no_lock input_file.ts
* Without this option, mecenc creates /tmp/encode\_movie.lock to lock other process.

# Dependencies
* g++
* python-opencv
* python-numpy
* libstdc++6:i386  # for NeroAacEnc(32bit) on 64bit Linux.
* ImageMagick
* sox
* x264
* x265 (optional)
* neroAacEnc
* ffmpeg (libx264, libx265 and libpng support is required)
* TBD...
