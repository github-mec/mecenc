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
HISTOGRAM_BIN_N = 64


def ParseLogoInformation(logo_name):
    logo_dir = os.path.join(
        os.path.abspath(os.path.dirname(__file__)), 'logo')
    required_keys = set(('offset_x', 'offset_y', 'width', 'height'))
    info = {}
    input_filename = '%s/%s.txt' % (logo_dir, logo_name)
    with open(input_filename) as input_file:
        for line in input_file:
            (key, value) = line.split(':')
            key.strip()
            value.strip()
            value = int(value)
            assert key in required_keys, (
                'Invalid key "%s" in %s' % (key, input_filename))
            assert value >= 0, (
                'Value for key "%s" in %s should be positive' % (
                    key, input_filename))
            assert value % 4 == 0, '%s should be in multiples of 4.' % key
            info[key] = int(value)
    assert len(required_keys) == len(info), (
        '%s should have all of %s' % (
            input_filename, [key for key in required_keys]))
    return info


def ParseOptions(args=None):
    parser = optparse.OptionParser()
    parser.add_option('--no_dump', dest='no_dump', default=False,
                      help='True if the input movie is already dumped.')
    parser.add_option('--scene_time_filter', dest='scene_time_filter',
                      default=None,
                      help=('Comma-separated [start,duration) of scene'
                            ' start/duration positions in sec.'))
    parser.add_option('--logo_info', dest='logo_info', default=None,
                      help=('logo information for the offset and the size'
                            'of logo.'))

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

    if options.logo_info is not None:
        # Smoke test
        ParseLogoInformation(options.logo_info)

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


def GetPeriodicalDumpDirname():
    dirname = "logo_dump"
    if not os.path.exists(dirname):
        os.makedirs(dirname)
    return dirname


def FilterSilenceRanges(options, start, end):
    if options.scene_time_filter is None:
        return ((start, end),)

    (filter_start, filter_duration) = map(
        float, options.scene_time_filter.split(','))
    filter_start = filter_start + int(start)
    result = []
    while filter_start < end:
        filter_end = filter_start + filter_duration
        if filter_start < start:
            if start < filter_end:
                result.append([start, filter_end])
        elif end < filter_end:
            result.append([filter_start, end])
        else:
            result.append([filter_start, filter_end])
        filter_start = filter_start + 1
    result.reverse()

    if len(result) == 0:
        return ()
    if end - 0.2 < result[-1][1]:
        result.insert(0, result.pop())
    return result


def GetDelay(filename):
    process = subprocess.Popen(
        ['ffmpeg', '-i', filename], stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    return float(re.search('Duration:.+start:\s+([\d\.]+)', output).group(1))


def DumpImages(options, movie_filename, frame_list):
    command = ['ffmpeg', '-i', '%s' % movie_filename]
    for i in xrange(len(frame_list)):
        dirname = GetDumpDirname(i)
        start = frame_list[i]['start']
        end = frame_list[i]['end'] + 1
        output_filename = '%s/%s.png' % (dirname, '%04d')
        command.extend([
                '-filter:v', (
                    'trim=start_frame=%d:end_frame=%d,separatefields'
                    ',scale=width=480:height=270' % (start, end)),
                '-qscale', '0.5',
                '-an',
                output_filename])

    if options.logo_info is not None:
        logo_info = ParseLogoInformation(options.logo_info)
        offset_x = logo_info['offset_x']
        offset_y = logo_info['offset_y']
        width = logo_info['width']
        height = logo_info['height']

        extra_offset_x = 4 if offset_x >= 4 else offset_x
        extra_offset_y = 4 if offset_y >= 4 else offset_y
        dirname = GetPeriodicalDumpDirname()
        output_filename = '%s/%s.png' % (dirname, '%06d')
        command.extend([
            '-filter:v', (
                'fps=fps=1:round=down'
                ',crop=%d:%d:%d:%d,yadif,crop=%d:%d:%d:%d' % (
                    width + 8, height + 8,
                    offset_x - extra_offset_x, offset_y - extra_offset_y,
                    width, height, extra_offset_x, extra_offset_y)),
            '-an',
            output_filename])

    process = subprocess.Popen(command, stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    if process.returncode != 0:
        logging.error('Failed to dump images.')
        sys.exit(process.returncode)


def CreateDumpedMovie(index):
    dirname = GetDumpDirname(index)
    input_filename = '%s/%s.png' % (dirname, '%04d')
    output_filename = '%s/dump.mp4v' % dirname
    command = ['ffmpeg', '-i', '%s' % input_filename]
    command.extend([
        '-an',
        '-vcodec', 'libx264',
        '-preset', 'veryfast',
        '-f', 'mp4',
        '-threads', '0',
        output_filename])
    process = subprocess.Popen(command, stdout=None, stderr=subprocess.PIPE)
    output = process.communicate()[1]
    if process.returncode != 0:
        logging.error('Failed to create a dumped movie. index:%d.', i)
        sys.exit(process.returncode)


def Dump(options, movie_filename, frame_list):
    DumpImages(options, movie_filename, frame_list)
    for i in xrange(len(frame_list)):
        CreateDumpedMovie(i)


def GetImageFilenames(image_dirname):
    image_filenames = []
    matcher = re.compile(r'\.png$')
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


def LoadHistogramsBgr(filename):
    im = cv2.imread(filename)
    if im == None:
        logging.error('Failed to load image as BGR. [%s]', filename)
        return None
    histograms = []
    for channel in cv2.split(im):
        histogram = cv2.calcHist(
            [channel], [0], None, [HISTOGRAM_BIN_N], [0, 256])
        cv2.normalize(histogram, histogram, alpha=1, norm_type=cv2.NORM_L1)
        histograms.append(histogram)
    return histograms


def ConvertForEmd(histogram):
    array = [(histogram[i][0], i)
             for i in xrange(HISTOGRAM_BIN_N)
             if histogram[i] > 0]
    f64 = cv.fromarray(numpy.array(array))
    f32 = cv.CreateMat(f64.rows, f64.cols, cv.CV_32FC1)
    cv.Convert(f64, f32)
    return f32


def CalcEmd(histograms1, histograms2):
    result = 0
    for i in xrange(len(histograms1)):
        data1 = ConvertForEmd(histograms1[i])
        data2 = ConvertForEmd(histograms2[i])
        distance = cv.CalcEMD2(data1, data2, cv.CV_DIST_L2) / HISTOGRAM_BIN_N
        result = result + distance ** 2
    return result ** 0.5


def LoadHistogramDistances(image_dirname):
    image_filenames = GetImageFilenames(image_dirname)
    histograms_list = [LoadHistogramsBgr(filename) for filename in image_filenames]
    return [CalcEmd(histograms_list[i - 1], histograms_list[i])
            for i in xrange(1, len(histograms_list))]


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
    if not frame['filtered_ranges']:
        return -1

    is_scene_time_filter_enabled = options.scene_time_filter is not None
    if is_scene_time_filter_enabled:
        check_first_frame = True
        trim_frames = 0
    else:
        check_first_frame = frame['start'] < 5
        trim_frames = 14

    distances = LoadHistogramDistances(dump_dirname)
    assert len(distances) == (frame['end'] - frame['start']) * 2 + 1, (
        'Cannot load the histograms of the dumped images.')

    filtered_distances = []
    start_offsets = []
    for filtered_range in frame['filtered_ranges']:
        start_offset = (filtered_range['start'] - frame['start']) * 2
        end_offset = (filtered_range['end'] - frame['start']) * 2 + 1
        start_offsets.append(start_offset)
        filtered_distances.append(distances[start_offset:end_offset])

    scene_change_frame = -1
    for i, d in enumerate(filtered_distances):
        scene_change_frame = AnalyzeDistances(
            d, threshold=0.3, trim=trim_frames,
            check_first_frame=check_first_frame)
        if scene_change_frame > 0:
            return scene_change_frame + start_offsets[i]

    gray_histograms = LoadGrayScaleHistogramList(dump_dirname)
    scene_change_frame = AnalyzeBlackWhiteFrame(
        gray_histograms, check_first_frame=check_first_frame)
    if scene_change_frame > 0:
        return scene_change_frame + start_offsets[i]

    for i, d in enumerate(filtered_distances):
        scene_change_frame = AnalyzeDistances(
            d, threshold=0.2, trim=trim_frames,
            check_first_frame=check_first_frame)
        if scene_change_frame > 0:
            return scene_change_frame + start_offsets[i]

    for i, d in enumerate(filtered_distances):
        scene_change_frame = AnalyzeDistances(d, threshold=0.2)
        if scene_change_frame > 0:
            return scene_change_frame + start_offsets[i]

    for i, d in enumerate(filtered_distances):
        scene_change_frame = AnalyzeDistances(d, threshold=0.1)
        if scene_change_frame > 0:
            return scene_change_frame + start_offsets[i]

    fallback_value = 0
    fallback_frame = -1
    for i, d in enumerate(filtered_distances):
        scene_change_frame = AnalyzeLastResort(d, threshold=0.03)
        if scene_change_frame > 0:
            return scene_change_frame + start_offsets[i]
        if scene_change_frame < fallback_value:
            fallback_value = scene_change_frame
            fallback_frame = scene_change_frame - start_offsets[i]

    return fallback_frame


def LoadSilenceFrameList(options, silence_filename, audio_delay):
    frame_list = []
    with open(silence_filename) as silence_file:
        # skip first line
        silence_file.readline()
        for line in silence_file:
            (start, end) = map((lambda x: float(x) - audio_delay),
                               line.strip().split(' '))
            result_ranges = []
            for filtered_range in FilterSilenceRanges(options, start, end):
                result_ranges.append({
                    'start': TimeToFrameNum(filtered_range[0]),
                    'end': TimeToFrameNum(filtered_range[1]) + 1,
                })
            frame_list.append({
                'start': TimeToFrameNum(start),
                'end': TimeToFrameNum(end) + 1,
                'filtered_ranges': result_ranges,
            })
    return frame_list


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
    frame_list = LoadSilenceFrameList(
        options, silence_filename, GetDelay(movie_filename))

    if not options.no_dump:
        # TODO: Extract dump logic as another script.
        Dump(options, movie_filename, frame_list)

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
            output_file.write('%s %s %d %d %s\n' % (
                i, mode, start, end, target))


if __name__ == '__main__':
#    logging.basicConfig(level=logging.INFO)
    Main()
    
