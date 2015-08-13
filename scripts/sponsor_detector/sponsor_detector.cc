#include "opencv2/opencv.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <memory>
#include <utility>
#include <vector>
using namespace std;

const int HSV_V_THRESHOLD = 220;
const int HSV_S_THRESHOLD = 20;
const int SMALL_WHITE_AREA_SIZE_THRESHOLD = 50;
const int SMALL_BLACK_AREA_SIZE_THRESHOLD = 16;
const int LARGE_AREA_SIZE_THRESHOLD = 1500;
const int SPONSOR_MARK_AREA_NUM = 7;

int image_width;
int image_height;
int image_size;
std::unique_ptr<bool[]> visited_field;
std::unique_ptr<bool[]> color_field;
const bool BLACK = false;
const bool WHITE = true;

size_t GetIndex(int x, int y) {
  return image_width * y + x;
}

bool IsValidIndex(int index) {
  return 0 <= index && index < image_size;
}

void ClearVisitedField() {
  memset(visited_field.get(), false, image_size);
}

bool LoadImage(const string &filename) {
  cv::Mat original_image = cv::imread(filename);
  if (!original_image.data) {
    return false;
  }

  image_width = original_image.cols;
  image_height = original_image.rows;
  image_size = image_width * image_height;
  visited_field.reset(new bool[image_width * image_height]);
  color_field.reset(new bool[image_width * image_height]);

  cv::Mat image;
  cv::cvtColor(original_image, image, CV_RGB2HSV);

  ClearVisitedField();
  for (int y = 0; y < image.rows; ++y) {
    cv::Vec3b *ptr = image.ptr<cv::Vec3b>(y);
    for (int x = 0; x < image.cols; ++x) {
      const cv::Vec3b &pixel = ptr[x];
      const int index = GetIndex(x, y);
      if (pixel[1] <= HSV_S_THRESHOLD &&
          pixel[2] >= HSV_V_THRESHOLD) {
        color_field[index] = WHITE;
      } else {
        color_field[index] = BLACK;
      }
    }
  }
  return true;
}

bool OutputImage(const string &filename) {
  cv::Mat output_image(image_height, image_width, CV_8U);
  if (!output_image.isContinuous()) {
    return false;
  }
  unsigned char *begin = output_image.ptr<unsigned char>(0);
  unsigned char *end = begin + image_size;
  for (int i = 0; i < image_size; ++i) {
    unsigned char *ptr = begin + i;
    if (color_field[i] == WHITE) {
      *ptr = 255;
    } else {
      *ptr = 0;
    }
  }
  cv::imwrite(filename, output_image);
}

bool AddSurroundingPositions(int base_index, vector<int> *positions) {
  assert(image_width > 0);
  // All edges should be visited by FillEdgeAreas.
  static const int index_delta[] = {
    -image_width,
    -1,
    1,
    image_width,
  };

  for (int i = 0; i < 4; ++i) {
    int index = base_index + index_delta[i];
    if (IsValidIndex(index) && !visited_field[index]) {
      positions->push_back(index);
    }
  }
}

bool IsAreaGreaterThanThreshold(int start_index, bool target_color,
                                int threshold) {
  int pixel_count = 0;
  vector<int> positions;
  set<int> local_visited_set;
  positions.push_back(start_index);
  while (!positions.empty()) {
    const int index = positions.back();
    positions.pop_back();
    if (visited_field[index] || !local_visited_set.insert(index).second) {
      continue;
    }
    if (color_field[index] != target_color) {
      continue;
    }
    ++pixel_count;
    if (pixel_count >= threshold) {
      return true;
    }
    AddSurroundingPositions(index, &positions);
  }
  return false;
}

void FillArea(int start_index, bool fill_color) {
  const bool target_color = color_field[start_index];
  vector<int> positions;
  positions.push_back(start_index);
  while (!positions.empty()) {
    const int index = positions.back();
    positions.pop_back();
    if (visited_field[index]) {
      continue;
    }
    if (color_field[index] != target_color) {
      continue;
    }
    color_field[index] = fill_color;
    visited_field[index] = true;
    AddSurroundingPositions(index, &positions);
  }
}

void FillAreasOnEdge() {
  for (int x = 0; x < image_width; ++x) {
    FillArea(GetIndex(x, 0), BLACK);
    FillArea(GetIndex(x, image_height - 1), BLACK);
  }
  for (int y = 0; y < image_height; ++y) {
    FillArea(GetIndex(0, y), BLACK);
    FillArea(GetIndex(image_width - 1, y), BLACK);
  }
}

void RemoveNoiseAreas(int threshold, bool color) {
  for (int index = 0; index < image_size; ++index) {
    if (visited_field[index] && color_field[index] != color) {
      continue;
    }
    if (!IsAreaGreaterThanThreshold(index, color, threshold)) {
      FillArea(index, !color);
    } else {
      FillArea(index, color);
    }
  }
}

void FillLargeAreas(int threshold) {
  for (int index = 0; index < image_size; ++index) {
    if (visited_field[index]) {
      continue;
    }
    const bool color = color_field[index];
    if (IsAreaGreaterThanThreshold(index, color, threshold)) {
      FillArea(index, BLACK);
    } else {
      FillArea(index, color);
    }
  }
}

bool IsWhiteAreaNumberGreaterThanThreshold(int size_threshold,
                                           int num_threshold) {
  int area_num = 0;
  for (int index = 0; index < image_size; ++index) {
    if (visited_field[index] || color_field[index] == BLACK) {
      continue;
    }
    if (IsAreaGreaterThanThreshold(index, WHITE, size_threshold)) {
      ++area_num;
      if (area_num >= num_threshold) {
        return true;
      }
      FillArea(index, WHITE);
    }
  }  
  return false;
}

int main(int argc, char *argv[]) {
  if (argc != 3) {
    cerr << "Please specify input / output" << endl;
    return -1;
  }
  const string input_filename = argv[1];
  const string output_filename = argv[2];

  if (!LoadImage(input_filename)) {
    cerr << "Could not load " << input_filename << endl;
    return -1;
  }

  // Early exit to improve performance.
  ClearVisitedField();
  if (!IsWhiteAreaNumberGreaterThanThreshold(
          SMALL_WHITE_AREA_SIZE_THRESHOLD, SPONSOR_MARK_AREA_NUM)) {
    // Could not find a sponsor logo candidate.
    return 1;
  }

  ClearVisitedField();
  RemoveNoiseAreas(SMALL_BLACK_AREA_SIZE_THRESHOLD, BLACK);

  ClearVisitedField();
  RemoveNoiseAreas(SMALL_WHITE_AREA_SIZE_THRESHOLD, WHITE);

  // Sponsor mark should NOT on the edge of a image.
  ClearVisitedField();
  FillAreasOnEdge();

  // Sponsor mark have edge, so large area should NOT be the mark.
  ClearVisitedField();
  FillLargeAreas(LARGE_AREA_SIZE_THRESHOLD);

  ClearVisitedField();
  if (!IsWhiteAreaNumberGreaterThanThreshold(1, SPONSOR_MARK_AREA_NUM)) {
    // Could not find a sponsor logo candidate.
    return 1;
  }

  OutputImage(output_filename);

  return 0;
}


