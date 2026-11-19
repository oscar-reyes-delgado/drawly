#ifndef RUNNER_VIDEO_ENCODER_H_
#define RUNNER_VIDEO_ENCODER_H_

#include <flutter/binary_messenger.h>

// Registers the "drawly/video" method channel: H.264 MP4 encoding with the
// Windows Media Foundation sink writer (part of the operating system).
//
// Methods:
//   available                                  -> bool
//   begin {path, width, height, fps, bitrate}  -> int handle
//   addFrame {id, rgba}                        -> null (straight RGBA, width*height*4)
//   finish {id}                                -> bool
//   abort {id}                                 -> null (deletes the partial file)
void RegisterVideoEncoder(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_VIDEO_ENCODER_H_
