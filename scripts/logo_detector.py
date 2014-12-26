#!/usr/bin/python

import cv2
import logging
import os
import re
import sys
import numpy
import optparse


def GetLogoFileName(options):
    return os.path.join(
        os.path.abspath(os.path.dirname(__file__)),
        '..',
        'logo',
        '%s.png' % options.logo)


def ParseOptions(args=None):
    parser = optparse.OptionParser()
    parser.add_option('--logo', dest='logo', default=None,
                      help=('The reference logo name in logo dir'
                            'w/o filename extension.'))
    (options, _) = parser.parse_args(args)
    return options


def LoadLogoRangeData(logo_image):
    col_num = len(logo_image[0])

    ranges = []
    for i in xrange(len(logo_image)):
        ranges.append([])

    for (y, row) in enumerate(logo_image):
        start = None
        for (x, value) in enumerate(row):
            if not value:
                if start is not None:
                    end = x
                    if 1 < end - start < 8:
                        color = float(sum(row[start:end])) / (end - start)
                        ranges[y].append((start, end, color))
                    start = None
                continue
            if start is None:
                start = x
    return ranges

    filtered_ranges = []
    for i in xrange(len(logo_image)):
        filtered_ranges.append([])

    for y, row in enumerate(ranges):
        if len(row) == 0:
            continue
        if row[0][0] >= 2:
            filtered_ranges[y].append(row[0])
        if len(row) == 1:
            continue
        for i in xrange(1, len(row) - 1):
            if (row[i - 1][1] + 3 <= row[i][0] and
                row[i][1] <= row[i + 1][0] + 3):
                filtered_ranges[y].append(row[i])
        if row[-1][1] <= col_num - 2:
            filtered_ranges[y].append(row[-1])
    return filtered_ranges


def RowDetect(logo_image_row, logo_range_row, target_row):
    discarded = 0
    detected = 0
    for start, end, color in logo_range_row:
        left = int(target_row[start - 2])
        right = int(target_row[end + 1])
        base_color = (left + right) / 2

        too_dark_color = False
        base_color_with_margin = base_color - 8
        dark_threshold = base_color / 2 - 8
        for x in xrange(start, end):
            # Please pay attention for performance.
            if target_row[x] < max(logo_image_row[x] + dark_threshold,
                                   base_color_with_margin):
                too_dark_color = True
                break
        if too_dark_color:
            continue

        if abs(left - right) > 8 or base_color > 192:
            discarded = discarded + 1
            continue

        target_average = sum(target_row[start:end]) / (end - start)
        if target_average > base_color + 8:
            detected = detected + 1
    return (detected, len(logo_range_row) - discarded)


def HorizontalDetect(logo_image, target_image):
    logo_range_data = LoadLogoRangeData(logo_image)
    assert len(logo_range_data) == len(target_image), (
           'Inconsistent image size. reference logo: %dpx, target: %dpx' % (
               len(logo_range_data), len(target_image)))

    candidate_sum = 0
    detected_sum = 0
    range_sum = 0
    for y in xrange(len(logo_range_data)):
        (detected_num, candidate_num) = RowDetect(
            logo_image[y], logo_range_data[y], target_image[y])
        candidate_sum = candidate_sum + candidate_num
        detected_sum = detected_sum + detected_num
        range_sum = range_sum + len(logo_range_data[y])
    return (detected_sum, candidate_sum, range_sum)


def Detect(logo_image, target_image, tag=''):
    detected_num = 0
    candidate_num = 0
    total_num = 0
    for i in xrange(2):
        if i == 0:
            (a, b, c) = HorizontalDetect(logo_image, target_image)
        else:
            (a, b, c) = HorizontalDetect(logo_image.T, target_image.T)
        detected_num = detected_num + a
        candidate_num = candidate_num + b
        total_num = total_num + c

    # Eligible if some of target pixels are NOT saturated.
    is_eligible = (candidate_num > 0 and candidate_num > total_num / 10.0)
    if is_eligible:
        detected_ratio = float(detected_num) / candidate_num
    else:
        detected_ratio = 0.0

    debug_print = False
    if debug_print:
        if not is_eligible:
            result_mark = '-'
        elif detected_ratio > 0.3:
            result_mark = 'o'
        else:
            result_mark = ' '
        print '%s: %c ratio:%.2f, count:%d' % (
            tag, result_mark, detected_ratio, candidate_num)

    return detected_ratio > 0.3


def Main():
    options = ParseOptions()
    logo_filename = GetLogoFileName(options)
    input_dirname = 'logo_dump'

    if not os.path.isfile(logo_filename):
        logging.error('Logo file is not found or not a file.')
        sys.exit(-1)
    if not os.path.isdir(input_dirname):
        logging.error('Input video directory is not found or not a directory.')
        sys.exit(-1)
    if os.path.exists('logo.txt'):
        logging.error('logo.txt already exists.')
        sys.exit(-1)

    logo_image = cv2.cvtColor(cv2.imread(logo_filename), cv2.COLOR_BGR2GRAY)

    image_path_regex = re.compile(r'\.(png|jpg)$')
    results = []
    for input_filename in sorted(os.listdir(input_dirname)):
        if not image_path_regex.search(input_filename):
            continue
        input_path = '%s/%s' % (input_dirname, input_filename)
        im = cv2.cvtColor(cv2.imread(input_path), cv2.COLOR_BGR2GRAY)
        results.append(Detect(logo_image, im, tag=input_filename))

    with open('logo.txt', 'w') as output_file:
        # 1-origin to keep a consistency with the output of ffmpeg.
        for i, result in enumerate(results):
            output_file.write('%06d %s\n' % (i + 1, result))
        

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    Main()
