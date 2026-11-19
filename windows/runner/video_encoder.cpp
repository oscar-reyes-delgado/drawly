#include "video_encoder.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <windows.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

template <class T>
void SafeRelease(T** p) {
  if (*p) {
    (*p)->Release();
    *p = nullptr;
  }
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

class Mp4Writer {
 public:
  ~Mp4Writer() { SafeRelease(&writer_); }

  HRESULT Begin(const std::wstring& path, UINT32 width, UINT32 height, UINT32 fps, UINT32 bitrate) {
    path_ = path;
    width_ = width;
    height_ = height;
    fps_ = fps;
    IMFAttributes* attrs = nullptr;
    IMFMediaType* out = nullptr;
    IMFMediaType* in = nullptr;
    HRESULT hr = MFCreateAttributes(&attrs, 1);
    if (SUCCEEDED(hr)) hr = attrs->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    if (SUCCEEDED(hr)) hr = MFCreateSinkWriterFromURL(path.c_str(), nullptr, attrs, &writer_);
    // output: H.264
    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&out);
    if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
    if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    if (SUCCEEDED(hr)) hr = MFSetAttributeSize(out, MF_MT_FRAME_SIZE, width, height);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(out, MF_MT_FRAME_RATE, fps, 1);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(out, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    if (SUCCEEDED(hr)) hr = writer_->AddStream(out, &stream_);
    // input: 32-bit BGRX, top-down rows
    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&in);
    if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_DEFAULT_STRIDE, width * 4);
    if (SUCCEEDED(hr)) hr = MFSetAttributeSize(in, MF_MT_FRAME_SIZE, width, height);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(in, MF_MT_FRAME_RATE, fps, 1);
    if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(in, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    if (SUCCEEDED(hr)) hr = writer_->SetInputMediaType(stream_, in, nullptr);
    if (SUCCEEDED(hr)) hr = writer_->BeginWriting();
    SafeRelease(&attrs);
    SafeRelease(&out);
    SafeRelease(&in);
    return hr;
  }

  // [rgba]: straight RGBA, composited over an opaque background by the caller.
  HRESULT AddFrame(const std::vector<uint8_t>& rgba) {
    const DWORD stride = width_ * 4;
    const DWORD size = stride * height_;
    if (rgba.size() < size) return E_INVALIDARG;
    IMFMediaBuffer* buffer = nullptr;
    IMFSample* sample = nullptr;
    HRESULT hr = MFCreateMemoryBuffer(size, &buffer);
    BYTE* dst = nullptr;
    if (SUCCEEDED(hr)) hr = buffer->Lock(&dst, nullptr, nullptr);
    if (SUCCEEDED(hr)) {
      const uint8_t* src = rgba.data();
      for (DWORD i = 0; i < size; i += 4) {
        dst[i] = src[i + 2];      // B
        dst[i + 1] = src[i + 1];  // G
        dst[i + 2] = src[i];      // R
        dst[i + 3] = 255;
      }
      buffer->Unlock();
    }
    if (SUCCEEDED(hr)) hr = buffer->SetCurrentLength(size);
    if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer);
    const LONGLONG duration = 10000000LL / fps_;
    if (SUCCEEDED(hr)) hr = sample->SetSampleTime(frame_ * 10000000LL / fps_);
    if (SUCCEEDED(hr)) hr = sample->SetSampleDuration(duration);
    if (SUCCEEDED(hr)) hr = writer_->WriteSample(stream_, sample);
    if (SUCCEEDED(hr)) frame_++;
    SafeRelease(&sample);
    SafeRelease(&buffer);
    return hr;
  }

  HRESULT Finish() {
    HRESULT hr = writer_ ? writer_->Finalize() : E_FAIL;
    SafeRelease(&writer_);
    return hr;
  }

  void Abort() {
    SafeRelease(&writer_);
    DeleteFileW(path_.c_str());
  }

 private:
  IMFSinkWriter* writer_ = nullptr;
  DWORD stream_ = 0;
  UINT32 width_ = 0, height_ = 0, fps_ = 12;
  LONGLONG frame_ = 0;
  std::wstring path_;
};

std::map<int, std::unique_ptr<Mp4Writer>> g_writers;
int g_next_id = 1;
bool g_mf_started = false;

bool EnsureMediaFoundation() {
  if (g_mf_started) return true;
  g_mf_started = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
  return g_mf_started;
}

const EncodableValue* Arg(const EncodableMap& m, const char* key) {
  auto it = m.find(EncodableValue(key));
  return it == m.end() ? nullptr : &it->second;
}

int ArgInt(const EncodableMap& m, const char* key, int fallback) {
  const EncodableValue* v = Arg(m, key);
  if (v == nullptr) return fallback;
  if (auto i = std::get_if<int32_t>(v)) return *i;
  if (auto l = std::get_if<int64_t>(v)) return static_cast<int>(*l);
  return fallback;
}

}  // namespace

void RegisterVideoEncoder(flutter::BinaryMessenger* messenger) {
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "drawly/video", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const std::string& name = call.method_name();
    if (name == "available") {
      result->Success(EncodableValue(EnsureMediaFoundation()));
      return;
    }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("args", "Missing arguments");
      return;
    }
    if (name == "begin") {
      const auto* path = std::get_if<std::string>(Arg(*args, "path"));
      const int w = ArgInt(*args, "width", 0), h = ArgInt(*args, "height", 0);
      const int fps = ArgInt(*args, "fps", 12), bitrate = ArgInt(*args, "bitrate", 8000000);
      if (path == nullptr || w <= 0 || h <= 0 || (w % 2) != 0 || (h % 2) != 0 || fps <= 0) {
        result->Error("args", "Invalid path, size (must be even) or fps");
        return;
      }
      if (!EnsureMediaFoundation()) {
        result->Error("mf", "Media Foundation is not available");
        return;
      }
      auto writer = std::make_unique<Mp4Writer>();
      HRESULT hr = writer->Begin(Utf8ToWide(*path), w, h, fps, bitrate);
      if (FAILED(hr)) {
        writer->Abort();
        result->Error("begin", "Could not start the video file", EncodableValue(static_cast<int64_t>(hr)));
        return;
      }
      const int id = g_next_id++;
      g_writers[id] = std::move(writer);
      result->Success(EncodableValue(id));
      return;
    }
    const int id = ArgInt(*args, "id", -1);
    auto it = g_writers.find(id);
    if (it == g_writers.end()) {
      result->Error("id", "Unknown video handle");
      return;
    }
    if (name == "addFrame") {
      const auto* rgba = std::get_if<std::vector<uint8_t>>(Arg(*args, "rgba"));
      HRESULT hr = rgba == nullptr ? E_INVALIDARG : it->second->AddFrame(*rgba);
      if (FAILED(hr)) {
        it->second->Abort();
        g_writers.erase(it);
        result->Error("frame", "Could not encode the frame", EncodableValue(static_cast<int64_t>(hr)));
        return;
      }
      result->Success();
    } else if (name == "finish") {
      HRESULT hr = it->second->Finish();
      g_writers.erase(it);
      result->Success(EncodableValue(SUCCEEDED(hr)));
    } else if (name == "abort") {
      it->second->Abort();
      g_writers.erase(it);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}
