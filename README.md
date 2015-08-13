# How to extract broadcaster watermark
    ./logo_extractor input_file.ts logo_name.txt start_time end_time
* Some of logo\_name.txt is available under logo/ directory.
* Specify analysis range of input\_file.ts by start\_time and end\_time.
* All frames in analysis range should have broadcaster warermark.

# How to use:

## Simple
    ./mecenc input_file_1.ts [input_file_2.ts ...]
* CM detection.
* Encode by x264.
* Convert the frame ratio from keep\_fps to 24fps and deinterlace.
* Shrink the movie to 1280 x 720 since almost all animations are created in this resolution.
* Don't use broadcaster watermark detection for CM detection.
* Working / output / log directory is in ~/enc/.

## Encode by x265
    ./mecenc --encoder x265 input_file.ts

## Enable broadcaster watermark detection
    ./mecenc --logo logo_name input_file.ts
* logo\_name.png and logo\_name.txt should be in a logo directory.

## CM detection only (don't encode)
    ./mecenc --analyze input_file.ts

## Encode with detected CM information (single files)
    ./mecenc --scenefile /path/to/scene.txt input_file.ts

## Encode with detected CM information (multiple files)
    ./mecenc --scenelistfile /path/to/yyyy-mm-dd_hhmm_scenelist.txt

## Encode with interlaced movie
    ./mecenc --interlaced input_file.ts

## Encode with keeping the original fps (mainly for 30 fps animation)
    ./mecenc --keep_fps input_file.ts

## Don't shrink the movie
    ./mecenc --no_scale input_file.ts

## Specify directories
    ./mecenc --tempdir tempdir --destdir destdir --logdir logdir input_file.ts

## Don't clean the working directory
    ./mecenc --no_clean input_file.ts

## Enable aggressive CM analysis mainly for manual CM detection.
    ./mecenc --aggressive_analysis input_file.ts

## Don't lock other mecenc
    ./mecenc --no_lock input_file.ts
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
* tesseract-ocr
* tesseract-ocr-jpn
* TBD...
