#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>
#include <memory>

using namespace std;

const size_t TS_PACKET_SIZE = 188;
const int PAT_PID = 0x00;
const int TOT_PID = 0x14;

class TsPacket {
public:
  enum PacketType {
    GENERIC,
    PAT,  // Program Association Table
    PMT,  // Program Map Table
    TOT,  // Time Offset Table
  };

  explicit TsPacket(const char *data) : data_((const unsigned char *)data) {
    is_good_ = (data_[0] == 4*16+7);
  };
  virtual ~TsPacket() {};

  virtual bool IsGood() const {
    return is_good_;
  }

  int GetPid() const {
    return (data_[1] & 0x1F) * 256 + data_[2];
  }

  string GetDumpString() const {
    return GetHeaderDumpString() + GetBodyDumpString();
  }

  string GetHeaderDumpString() const {
    ostringstream ss;
    ss << "magic:\t" << (int)data_[0] << "\n";
    ss << "t indicator:\t" << (bool)(data_[1] & 0x80) << "\n";
    ss << "p indicator:\t" << (bool)(data_[1] & 0x40) << "\n";
    ss << "priority:\t" << (bool)(data_[1] & 0x20) << "\n";
    ss << "Program ID:\t" << (data_[1] & 0x1F) * 256 + data_[2] << "\n";
    ss << "s control:\t" << ((data_[3] & 0x60) >> 6) << "\n";
    ss << "a control:\t" << ((data_[3] & 0x30) >> 4) << "\n";
    ss << "Counter:\t" << (data_[3] & 0x0F) << "\n";
    return ss.str();
  }

  virtual string GetBodyDumpString() const {
    ostringstream ss;
    ss << hex;
    int j = 0;
    for (int i = 4; i < 188; ++i) {
      ss << setw(2) << setfill('0') << (int)data_[i] << " ";
      if (++j == 8) {
        ss << "\n";
        j = 0;
      }
    }
    return ss.str();
  }

  virtual PacketType GetPacketType() const {
    return GENERIC;
  }

protected:
  const unsigned char *data_;
  bool is_good_;
};

class TsPatPacket : public TsPacket {
public:
  explicit TsPatPacket(const char *data)
    : TsPacket(data), pmt_offset_(13) {
    const int section_length = (int)(data_[6] & 0x0F) * 256 + data_[7];
    pmt_number_ = (section_length - 9) / 4;
  };
  virtual ~TsPatPacket() {};

  virtual bool IsGood() const {
    return TsPacket::IsGood() && GetPid() == PAT_PID;
  }

  virtual string GetBodyDumpString() const {
    ostringstream ss;
    ss << "------ PAT ------" << "\n";
    if (data_[4] != 0) {
      ss << "Unknown pointer field... :(" << "\n";
      return ss.str();
    }
    ss << "table ID:\t" << (int)data_[5] << "\n";
    ss << "selection syntax indicator:\t" << (bool)(data_[6] & 0x80) << "\n";
    const int section_length = (int)(data_[6] & 0x0F) * 256 + data_[7];
    ss << "section_length:\t" << section_length << "\n";
    ss << "transport stream id:\t" << ((int)data_[8] * 256 + data_[9]) << "\n";
    ss << "version number:\t" << ((data_[10] >> 1) & 0x1F) << "\n";
    ss << "current next indicator:\t" << (bool)(data_[10] & 0x01) << "\n";
    ss << "section number:\t" << (int)data_[11] << "\n";
    ss << "last section number:\t" << (int)data_[12] << "\n";

    for (int i = 0; i < pmt_number_; ++i) {
      const int offset = pmt_offset_ + i * 4;
      const int program_number = (int)data_[offset] * 256 + data_[offset + 1];
      ss << "  " << i << " program_number:\t" << program_number << "\n";
      ss << "  " << i << " ";
      const int value = (int)(data_[offset + 2] & 0x1F) * 256 + data_[offset + 3];
      if (program_number == 0) { 
       ss << "network_PID:\t";
      } else {
        ss << "program map PID:\t";
      }
      ss << value << "\n";
    }
    // CRC 4bytes

    return ss.str();
  }

  void GetPmtPids(vector<int> *output) const {
    output->clear();
    for (int i = 0; i < pmt_number_; ++i) {
      const int offset = pmt_offset_ + i * 4;
      const int program_number = (int)data_[offset] * 256 + data_[offset + 1];
      if (program_number != 0) {
        output->push_back((int)(data_[offset + 2] & 0x1F) * 256 + data_[offset + 3]);
      }
    }
  }

  virtual PacketType GetPacketType() const {
    return PAT;
  }

private:
  int pmt_number_;
  int pmt_offset_;
};

class TsPmtPacket : public TsPacket {
public:
  explicit TsPmtPacket(const char *data)
    : TsPacket(data) {
    const size_t program_info_length = ((size_t)data_[15] & 0x0F) * 256 + data_[16];
    const size_t section_length = (size_t)(data_[6] & 0x0F) * 256 + data_[7];
    supported_ = (data_[4] == 0);  // There are unknown pointer fields or not.
    id_offset_ = 17 + program_info_length;
    id_length_ = section_length - program_info_length - 9;
  }

  virtual ~TsPmtPacket() {};

  virtual bool IsGood() const {
    return is_good_ && TsPacket::IsGood();
  }

  virtual string GetBodyDumpString() const {
    ostringstream ss;
    ss << "------ PMT ------" << "\n";
    if (data_[4] != 0) {
      ss << "Unknown pointer field... :(" << "\n";
      return ss.str();
    }
    ss << "table ID:\t" << (int)data_[5] << "\n";
    ss << "selection syntax indicator:\t" << (bool)(data_[6] & 0x80) << "\n";
    const int section_length = (int)(data_[6] & 0x0F) * 256 + data_[7];
    ss << "section_length:\t" << section_length << "\n";
    ss << "program number:\t" << ((int)data_[8] * 256 + data_[9]) << "\n";
    ss << "version number:\t" << ((data_[10] >> 1) & 0x1F) << "\n";
    ss << "current next indicator:\t" << (bool)(data_[10] & 0x01) << "\n";
    ss << "section number:\t" << (int)data_[11] << "\n";
    ss << "last section number:\t" << (int)data_[12] << "\n";
    ss << "PCR PID:\t" << (((int)data_[13] & 0x1F) * 256 + data_[14]) << "\n";
    const int program_info_length = ((int)data_[15] & 0x0F) * 256 + data_[16];
    ss << "program info length:\t" << program_info_length << "\n";
    // leads program info

    const int body_size = section_length - program_info_length - 9;
    const int offset = 17 + program_info_length;
    int pos = 0;
    while (pos < body_size) {
      const int stream_id = (int)data_[offset + pos];
      ss << "  stream ID:\t" << stream_id;
      if (stream_id == 0x02) {
        ss << " (movie)\n";
      } else if (stream_id == 0x0F) {
        ss << " (audio)\n";
      } else {
        ss << " (unknown...exit)\n";
        break;
      }
      ss << "  elem PID:\t" << (((int)data_[offset + pos + 1] & 0x01) * 256 + data_[offset + pos + 2]) << "\n";
      const int descriptor_length = ((int)data_[offset + pos + 3] & 0x0F) * 256 + data_[offset + pos + 4];
      pos += 5 + descriptor_length;
    }
    // CRC 4bytes

    return ss.str();
  }

  int GetFirstMovieId() const {
    return NextElementId(0x02);
  }

  int GetFirstAudioId() const {
    return NextElementId(0x0F);
  }

  virtual PacketType GetPacketType() const {
    return PMT;
  }

private:
  int NextElementId(int stream_id) const {
    if (!supported_) {
      return -1;
    }
    size_t offset = id_offset_;
    while (offset < id_length_) {
      int sid = (int)data_[offset];
      int eid = (int)(data_[offset + 1] & 0x01) * 256 + data_[offset + 2];
      if (sid == stream_id) {
        return eid;
      }
      const int descriptor_length = ((int)data_[offset + 3] & 0x0F) * 256 + data_[offset + 4];
      offset += 5 + descriptor_length;
    }
    return -1;
  }

  bool supported_;
  size_t id_offset_;
  size_t id_length_;
};

class TsTotPacket : public TsPacket {
public:
  explicit TsTotPacket(const char *data)
    : TsPacket(data) {
  }

  virtual ~TsTotPacket() {};

  virtual bool IsGood() const {
    return TsPacket::IsGood() && GetPid() == TOT_PID;
  }

  virtual string GetBodyDumpString() const {
    ostringstream ss;
    if (data_[4] != 0) {
      ss << "Unknown pointer field... :(" << "\n";
      return ss.str();
    }
    ss << "table ID:\t" << (int)data_[5] << "\n";
    ss << "selection syntax indicator:\t" << (bool)(data_[6] & 0x80) << "\n";
    const int section_length = (int)(data_[6] & 0x0F) * 256 + data_[7];
    ss << "section_length:\t" << section_length << "\n";
    // data_[8, 9] indicates date, maybe in hex.
    ss << "time:\t" << setw(2) << setfill('0') << GetHours() << ":"
                    << setw(2) << setfill('0') << GetMinutes() << ":"
                    << setw(2) << setfill('0') << GetSeconds();

    return ss.str();
  }

  int GetHours() const {
    int value = data_[10];
    return ((value & 0xF0) >> 4) * 10 + (value & 0x0F);
  }

  int GetMinutes() const {
    int value = data_[11];
    return ((value & 0xF0) >> 4) * 10 + (value & 0x0F);
  }

  int GetSeconds() const {
    int value = data_[12];
    return ((value & 0xF0) >> 4) * 10 + (value & 0x0F);
  }

  virtual PacketType GetPacketType() const {
    return TOT;
  }
};

class TsIterator {
public:
  TsIterator(const char *buf, size_t size)
    : data_(buf), data_size_(size), current_offset_(0) {
    Next();
  }

  size_t GetCurrentOffset() const {
    return current_offset_;
  }

  bool Next() {
    if (current_offset_ + TS_PACKET_SIZE * 2 > data_size_) {
      current_packet_.reset();
      return false;
    }
    current_offset_ += TS_PACKET_SIZE;
    return LoadDataToCurrentPacket();
  }

  bool Previous() {
    if (current_offset_ < TS_PACKET_SIZE) {
      current_packet_.reset();
      return false;
    }
    current_offset_ -= TS_PACKET_SIZE;
    return LoadDataToCurrentPacket();
  }

  bool Next(TsPacket::PacketType type) {
    if (type == TsPacket::GENERIC) {
      return Next();
    }

    while (Next()) {
      if (current_packet_->GetPacketType() == type) {
        return true;
      }
    }
    current_packet_.reset();
    return false;
  }

  bool Previous(TsPacket::PacketType type) {
    if (type == TsPacket::GENERIC) {
      return Previous();
    }

    while (Previous()) {
      if (current_packet_->GetPacketType() == type) {
        return true;
      }
    }
    current_packet_.reset();
    return false;
  }

  TsPacket *GetTsPacket() const {
    return current_packet_.get();
  }

 private:
  bool LoadDataToCurrentPacket() {
    const char *ts_data = data_ + current_offset_;
    current_packet_.reset(new TsPacket(ts_data));
    const int pid = current_packet_->GetPid();
    
    if (pid == PAT_PID) {
      current_packet_.reset(new TsPatPacket(ts_data));
      UpdatePmtPids();
    } else if (pid == TOT_PID) {
      current_packet_.reset(new TsTotPacket(ts_data));
    } else if (binary_search(pmt_pids_.begin(), pmt_pids_.end(), pid)) {
      current_packet_.reset(new TsPmtPacket(ts_data));
    }

    if (!current_packet_->IsGood()) {
      current_packet_.reset();
      return false;
    }

    return true;
  }

  void UpdatePmtPids() {
    if (current_packet_->GetPid() == 0 && current_packet_->IsGood()) {
      TsPatPacket *pat_packet =
        dynamic_cast<TsPatPacket *>(current_packet_.get());
      if (pat_packet) {
        pat_packet->GetPmtPids(&pmt_pids_);
      }
    }
  }

  const char *data_;
  const size_t data_size_;
  size_t current_offset_;
  TsPacket::PacketType current_packet_type_;
  unique_ptr<TsPacket> current_packet_;
  vector<int> pmt_pids_;
};

bool FileExists(const string &filename) {
  ifstream ifs(filename);
  return ifs.good();
}

int main(int argc, char *argv[]) {
  if (argc != 3) {
    cerr << "Please specify the input/output file." << endl;
    return 1;
  }

  const string input_filename = argv[1];
  const string output_filename = argv[2];

  const bool use_stdin = input_filename == "-";
  const bool use_stdout = output_filename == "-";
  ifstream input_file_stream;
  ofstream output_file_stream;
  istream *input_stream = nullptr;
  ostream *output_stream = nullptr;

  if (use_stdin) {
    input_stream = &cin;
  } else {
    if (!FileExists(input_filename)) {
      cerr << "No such file or directory. " << input_filename << endl;
      return 2;    
    }
    input_file_stream.open(input_filename, ios::in | ios::binary);
    input_stream = &input_file_stream;
  }

  if (use_stdout) {
    output_stream = &cout;
  } else {
    if (FileExists(output_filename)) {
      cerr << "Output file already exists. " << output_filename << endl;
      return 2;    
    }
    output_file_stream.open(output_filename, ios::out | ios::binary);
    output_stream = &output_file_stream;
  }

  const int kTotalPacketNum = 500 * 1000;
  const size_t file_content_buf_size = TS_PACKET_SIZE * kTotalPacketNum;
  unique_ptr<char []> file_content(new char[file_content_buf_size]);
  input_stream->read(file_content.get(), file_content_buf_size);
  const size_t loaded_size = input_stream->tellg();

  int movie_element_id = -1;
  {  // Determine the stream ID.
    const size_t offset = ((loaded_size / 2) / TS_PACKET_SIZE) * TS_PACKET_SIZE;
    TsIterator ts_iterator(file_content.get() + offset, loaded_size - offset);
    while (movie_element_id == -1) {
      if (!ts_iterator.Next(TsPacket::PMT)) {
        cerr << "Failed to find PMT packet." << endl;
        return -1;
      }
      const TsPmtPacket *packet =
        dynamic_cast<const TsPmtPacket *>(ts_iterator.GetTsPacket());
      movie_element_id = packet->GetFirstMovieId();
    }
  }

  {  // Detect first packet and write.
    size_t found_pos = 0;
    TsIterator ts_iterator(file_content.get(), loaded_size);

    // Usually, A TOT packet is in each 5 seconds.
    // Skip packets before hh:mm:55.
    const TsTotPacket *tot_packet = nullptr;
    do {
      ts_iterator.Next(TsPacket::TOT);
      tot_packet = dynamic_cast<const TsTotPacket *>(ts_iterator.GetTsPacket());
    } while (tot_packet->GetSeconds() > 15);  // 5sec is enough, but for safety.
    ts_iterator.Previous(TsPacket::TOT);

    while (ts_iterator.Next(TsPacket::PMT)) {
      const TsPmtPacket *pmt_packet =
        dynamic_cast<const TsPmtPacket *>(ts_iterator.GetTsPacket());
      if (pmt_packet->GetFirstMovieId() == movie_element_id) {
        found_pos = ts_iterator.GetCurrentOffset();
        break;
      }
    }

    ts_iterator.Previous(TsPacket::PAT);
    if (found_pos > ts_iterator.GetCurrentOffset()) {
      ts_iterator.Next(TsPacket::PAT);
    }
    const size_t start_offset = ts_iterator.GetCurrentOffset();
    output_stream->write(
        file_content.get() + start_offset, loaded_size - start_offset);
  }

  // Write a trailing content.
  while (input_stream->good()) {
    input_stream->read(file_content.get(), file_content_buf_size);
    output_stream->write(file_content.get(), input_stream->gcount());
  }

  return 0;
}

