#!/usr/bin/python

import cv
import cv2
import logging
import math
import optparse
import os
import re
import subprocess
import sys
import numpy


FRAME_DURATION = 1001 / 30000.0
HISTOGRAM_3D_BIN_N = 12


def ParseOptions(args=None):
    parser = optparse.OptionParser()
    parser.add_option('--no_dump', dest='no_dump', default=False,
                      help='True if the input movie is already dumped.')
    parser.add_option('--scene_time_filter', dest='scene_time_filter',
                      default=None,
                      help=('Comma-separated [start,duration) of scene'
                            ' start/end positions in sec.'))
    (options, _) = parser.parse_args(args)

    if options.scene_time_filter is not None:
        (filter_start, filter_duration) = map(
            float, options.scene_time_filter.split(','))
        if not 0 <= filter_start < 1:
            raise ValueError(
                'Start position of the CM time filter should be in [0,1)')
        if not 0 <= filter_duration < 1:
            raise ValueError(
                'Duration of the CM time filter should be in [0,1)')

    return options


def TimeToFrameNum(time):
    return max(0, int(time / FRAME_DURATION))


def FrameNumToTime(frame_num):
    return frame_num * FRAME_DURATION


def GetDumpDirname(scene_index):
    dirname = "dump/%03d" % scene_index
    if not os.path.exists(dirname):
        os.makedirs(dirname)
    return dirname


#TODO: Return multiple ranges.
def FilterSilenceTime(options, start, end):
    if options.scene_time_filter is None:
        return [start, end]

    (filter_start, filter_duration) = map(
        float, options.scene_time_filter.split(','))
    filter_start = filter_start + int(start)
    while filter_start < end:
        filter_end = filter_start + filter_duration
        if filter_start < start:
            if start < filter_end:
                return [start, filter_end]
        elif end < filter_end:
            return [filter_start, end]
        else:
            return [filter_start, filter_end]
        filter_start = filter_start + 1
    return [start, end]


def GetDelay(filename):
    process = subprocess.Popen(
        ['ffmpeg', '-i', filename], stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    return float(re.search('Duration:.+start:\s+([\d\.]+)', output).group(1))


def DumpMoviesInternal(movie_filename, frame_list, file_index_offset):
    command = ['ffmpeg', '-i', '%s' % movie_filename]
    output_filenames = []
    for i in xrange(len(frame_list)):
        dirname = GetDumpDirname(i + file_index_offset)
        start = frame_list[i][0]
        end = frame_list[i][1] + 1
        output_filename = '%s/dump.mp4v' % dirname
        output_filenames.append(output_filename)
        command.extend([
                '-filter:v', (
                    'trim=start_frame=%d:end_frame=%d,separatefields'
                    ',setpts=PTS-STARTPTS' % (start, end)),
                '-vcodec', 'libx264',
                '-an',
                '-preset', 'veryfast',
                '-f', 'mp4',
                '-threads', '4',
                output_filename])

    process = subprocess.Popen(command, stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    if process.returncode != 0:
        logging.error('Failed to dump movies.')
        sys.exit(process.returncode)
    
    return output_filenames


def DumpMovies(movie_filename, frame_list):
    # Limit parallel num due to memory limit. 30
    # e.g. parallel encode consumes 6-8GB memory.
    # TODO: Dump images directly instead of movies.
    MAX_PARALLEL_NUM = 16
    total_num = len(frame_list)
    parallel_num = total_num % MAX_PARALLEL_NUM
    parallel_num = parallel_num if parallel_num != 0 else MAX_PARALLEL_NUM
    consumed_num = 0
    output_filenames = []
    while consumed_num < total_num:
        start = consumed_num
        end = consumed_num + parallel_num
        output_filenames.extend(
            DumpMoviesInternal(movie_filename, frame_list[start:end], start))
        consumed_num = end
        parallel_num = min(total_num - consumed_num, MAX_PARALLEL_NUM)
    return output_filenames


def DumpImages(movie_filename, scene_index):
    dump_dirname = GetDumpDirname(scene_index)
    command = ['ffmpeg', '-i', movie_filename]
    command.extend([
            '-filter:v', 'scale=width=480:height=270',
            '-qscale', '1',
            '%s/%s' % (dump_dirname, "%04d.jpg")])

    process = subprocess.Popen(command, stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    if process.returncode != 0:
        logging.error('Failed to dump images.')
        sys.exit(process.returncode)


def Dump(movie_filename, frame_list):
    movie_dump_filenames = DumpMovies(movie_filename, frame_list)
    for i in xrange(len(movie_dump_filenames)):
        DumpImages(movie_dump_filenames[i], i)


def GetImageFilenames(image_dirname):
    image_filenames = []
    matcher = re.compile(r'\.jpg$')
    for filename in sorted(os.listdir(image_dirname)):
        if matcher.search(filename):
            image_filenames.append(os.path.join(image_dirname, filename))
    return image_filenames


def AnalyzeMovie(dirname):
    filename = os.path.join(dirname, 'dump.mp4v')
    command = ['ffmpeg',
               '-i', filename,
               '-filter:v', 'showinfo',
               '-f', 'null',
               '-y',
               '/dev/null']
    process = subprocess.Popen(command, stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    if process.returncode != 0:
        logging.error('Failed to dump images.')
        sys.exit(process.returncode)

    matcher = re.compile(r'n:(\d+) .+ type:I ')
    for line in output.split('\n'):
        m = matcher.search(line)
        if not m:
            continue
        frame_num = int(m.group(1))
        if frame_num != 0:
            return frame_num

    return 0


def Load3dHistogramBgr(filename):
    im = cv2.imread(filename)
    if im == None:
        logging.error('Failed to load image as BGR. [%s]', filename)
        return None
    histogram = cv2.calcHist(
        cv2.split(im), [0, 1, 2], None,
        [HISTOGRAM_3D_BIN_N, HISTOGRAM_3D_BIN_N, HISTOGRAM_3D_BIN_N],
        [0, 256, 0, 256, 0, 256])
    cv2.normalize(histogram, histogram, alpha=1, norm_type=cv2.NORM_L1)
    return histogram


def ConvertForEmd(histogram):
    array = [(histogram[b_i][g_i][r_i], b_i, g_i, r_i)
             for b_i in xrange(HISTOGRAM_3D_BIN_N)
             for g_i in xrange(HISTOGRAM_3D_BIN_N)
             for r_i in xrange(HISTOGRAM_3D_BIN_N)
             if histogram[b_i][g_i][r_i] > 0]
    f64 = cv.fromarray(numpy.array(array))
    f32 = cv.CreateMat(f64.rows, f64.cols, cv.CV_32FC1)
    cv.Convert(f64, f32)
    return f32


def CalcEmd(histogram1, histogram2):
    data1 = ConvertForEmd(histogram1)
    data2 = ConvertForEmd(histogram2)
    return cv.CalcEMD2(data1, data2, cv.CV_DIST_L2) / HISTOGRAM_3D_BIN_N


def Load3dHistogramDistances(image_dirname):
    # TODO: 3D histogram distance is overkill and consume CPU resources.
    #       Let's use three 1D histogram distance instead.
    image_filenames = GetImageFilenames(image_dirname)
    histograms = [Load3dHistogramBgr(filename) for filename in image_filenames]
    return [CalcEmd(histograms[i - 1], histograms[i])
            for i in xrange(1, len(histograms))]


def LoadGrayScaleHistogram(filename):
    im = cv2.cvtColor(cv2.imread(filename), cv2.COLOR_BGR2GRAY)
    if im == None:
        logging.error('Failed to load image as HSV. [%s]', filename)
        return None
    histogram = cv2.calcHist(im, [0], None, [256], [0, 256])
    cv2.normalize(histogram, histogram, 0, 255, cv2.NORM_L1)
    return histogram


def LoadGrayScaleHistogramList(image_dirname):
    image_filenames = GetImageFilenames(image_dirname)
    return [LoadGrayScaleHistogram(filename) for filename in image_filenames]


def AnalyzeDistances(
    distances, threshold, trim=0, check_first_frame=False):
    if trim * 3 > len(distances):
        trim = len(distances) / 3
    start = 0 if check_first_frame else trim
    end = len(distances) - trim
    # i + 1 since this method return the first frame of the a scene.
    results = [i + 1
               for i in xrange(start, end)
               if distances[i] >= threshold]
    return results[0] if len(results) >= 1 else 0


def AnalyzeBlackWhiteFrame(gray_histograms, check_first_frame):
    for loop in xrange(2):
        prev_total = 1e5  # 1e4 < 1e5 < 1e7
        for hist_i in xrange(len(gray_histograms)):
            histogram = gray_histograms[hist_i].tolist()
            # Check white or black frame
            if loop == 1:
                histogram.reverse()
            total = 0
            for i in xrange(len(histogram)):
                total = total + histogram[i][0] * i ** 2
            if ((total < 1e4 and prev_total > 1e7) or
                (total > 1e7 and prev_total < 1e4)):
                return hist_i
            prev_total = total
    return 0


def AnalyzeLastResort(distances, threshold):
    max_value = max(distances)
    result = distances.index(max_value) + 1
    return result if max_value > threshold else -result


def Analyze(options, dump_dirname, frame):
    if frame['filtered_start'] == frame['filtered_end']:
        return 0

    is_scene_time_filter_enabled = options.scene_time_filter is not None
    if is_scene_time_filter_enabled:
        check_first_frame = True
        trim_frames = 0
    else:
        check_first_frame = frame['start'] < 5
        trim_frames = 14

    distances = Load3dHistogramDistances(dump_dirname)
    assert len(distances) == (frame['end'] - frame['start']) * 2 + 1

    start_offset = (frame['filtered_start'] - frame['start']) * 2
    end_offset = (frame['filtered_end'] - frame['start']) * 2 + 1
    distances = distances[start_offset:end_offset]

    scene_change_frame = 0
    for _ in xrange(1):
        scene_change_frame = AnalyzeDistances(
            distances, threshold=0.3, trim=trim_frames,
            check_first_frame=check_first_frame)
        if scene_change_frame > 0:
            break

        gray_histograms = LoadGrayScaleHistogramList(dump_dirname)
        scene_change_frame = AnalyzeBlackWhiteFrame(
            gray_histograms, check_first_frame=check_first_frame)
        if scene_change_frame > 0:
            break

        scene_change_frame = AnalyzeDistances(
            distances, threshold=0.2, trim=trim_frames,
            check_first_frame=check_first_frame)
        if scene_change_frame > 0:
            break

        scene_change_frame = AnalyzeDistances(distances, threshold=0.2)
        if scene_change_frame > 0:
            break

        #   AnalyzeMovie cannot handle interlaced frame correctly.
        #    scene_change_frame = AnalyzeMovie()
        #    if scene_change_frame > 0:
        #        continue scene_change_frame

        scene_change_frame = AnalyzeLastResort(distances, threshold=0.03)
        if scene_change_frame > 0:
            break

    if scene_change_frame > 0:
        return scene_change_frame + start_offset
    elif scene_change_frame < 0:
        return scene_change_frame - start_offset
    else:
        return 0


def Main():
    movie_filename = 'in.mp4v'
    silence_filename = 'silence.txt'
    output_filename = 'scene.txt'

    if not os.path.isfile(silence_filename):
        logging.error('%s is not found.', silence_filename)
        return
    if not os.path.isfile(movie_filename):
        logging.error('%s is not a file.', movie_filename)
        return
    if os.path.isfile(output_filename):
        logging.error('%s already exists.', output_filename)
        return

    options = ParseOptions()

    frame_list = []
    with open(silence_filename) as silence_file:
        # skip first line
        silence_file.readline()
        movie_delay = GetDelay(movie_filename)
        time_list = []
        for line in silence_file:
            (start, end) = map((lambda x: float(x) - movie_delay),
                               line.strip().split(' '))
            (filtered_start, filtered_end) = FilterSilenceTime(
                options, start, end)
            time_list.append([start, filtered_start, filtered_end, end])
        for item in time_list:
            frame_list.append({
                'start': TimeToFrameNum(item[0]),
                'filtered_start': TimeToFrameNum(item[1]),
                'filtered_end': TimeToFrameNum(item[2]) + 1,
                'end': TimeToFrameNum(item[3]) + 1,
            })

    if not options.no_dump:
        Dump(movie_filename, frame_list)

    results = [Analyze(options, GetDumpDirname(i), frame_list[i])
               for i in xrange(len(frame_list))]

    assert len(frame_list) == len(results)
    with open(output_filename, 'w') as output_file:
        for i in xrange(len(results)):
            result = results[i]
            if result > 0:
                mode = 'exact'
            else:
                mode = 'range'
                result = -result
            start = frame_list[i]['start']
            end = frame_list[i]['end']
            if result % 2 == 0:
                target = '%d' % (start + result / 2)
            else:
                target = '%.1f' % round(start + result / 2.0, 1)
            output_file.write('%s %s %d %d %s\n' % (i, mode, start, end, target))


def MainTest():
    print AnalyzeStrictSceneChangeByImages('.', True)


if __name__ == '__main__':
#    logging.basicConfig(level=logging.INFO)
    Main()
#    MainTest()
    
