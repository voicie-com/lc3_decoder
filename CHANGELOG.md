## 0.1.1

* Add streaming LC3 header sample-count rewriting.
* Reject streams that end before the complete LC3 header is received.

## 0.1.0

* Add streaming LC3 to Ogg Opus transcoding.
* Add exact Ogg Opus duration reading from granule positions.

## 0.0.3

* LC3 audio decoding via FFI bindings to liblc3
* Cross-platform support: Android, iOS, macOS, Windows, Linux
* Simple API with `Lc3Decoder` class
* Automatic native library build via hooks
* Full-featured example app with GUI
  * File picker for LC3 files
  * Decode to PCM or WAV format
  * Progress tracking and performance metrics
  * Share/export functionality
* Comprehensive API documentation
