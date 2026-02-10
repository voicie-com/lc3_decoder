# LC3 Decoder

A Flutter FFI plugin for decoding LC3 (Low Complexity Communication Codec) audio.

## Overview

This package provides a high-performance LC3 audio decoder for Flutter applications via native FFI bindings. LC3 is a modern, low-latency audio codec designed for wireless audio applications, offering excellent audio quality at low bitrates.

## Features

- ✅ **Native Performance** - Direct FFI bindings to the official LC3 C implementation
- ✅ **Cross-Platform** - Supports Android, iOS, macOS, Windows, and Linux
- ✅ **Low Latency** - Optimized for real-time audio applications
- ✅ **Simple API** - Easy-to-use decoder interface
- ✅ **Automatic Build** - Native code compilation handled via build hooks
- ✅ **Example App** - Full-featured GUI example with file picker and playback

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android  | ✅ Supported |
| iOS      | ✅ Supported |
| macOS    | ✅ Supported |
| Windows  | ✅ Supported |
| Linux    | ✅ Supported |

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  lc3_decoder: ^0.0.3
```

Then run:

```bash
flutter pub get
```

## Usage

### Basic Example

```dart
import 'package:lc3_decoder/lc3_decoder.dart';
import 'dart:typed_data';

// Create a decoder instance
// Parameters: frame duration (μs), sample rate (Hz)
final decoder = Lc3Decoder(10000, 16000); // 10ms frames at 16kHz

// Decode an LC3 frame
Uint8List compressedFrame = /* your LC3 frame data */;
Uint8List pcmData = decoder.decode(compressedFrame);

// Don't forget to dispose when done
decoder.dispose();
```

### Complete Example

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:lc3_decoder/lc3_decoder.dart';

void decodeLC3File(String inputPath, String outputPath) {
  // Read LC3 file
  final inputFile = File(inputPath);
  final bytes = inputFile.readAsBytesSync();
  
  // Initialize decoder (adjust parameters to match your file)
  final decoder = Lc3Decoder(10000, 16000); // 10ms frames, 16kHz
  
  // Decode frames
  final outputBuffer = BytesBuilder();
  int offset = 0;
  
  while (offset < bytes.length) {
    // Read frame size (2 bytes, little-endian)
    final frameSize = bytes[offset] | (bytes[offset + 1] << 8);
    offset += 2;
    
    // Extract frame data
    final frameData = bytes.sublist(offset, offset + frameSize);
    offset += frameSize;
    
    // Decode frame
    final pcmData = decoder.decode(frameData);
    outputBuffer.add(pcmData);
  }
  
  // Save PCM output
  File(outputPath).writeAsBytesSync(outputBuffer.toBytes());
  
  // Clean up
  decoder.dispose();
  print('Decoding complete!');
}
```

## API Reference

### `Lc3Decoder`

Main decoder class for LC3 audio.

#### Constructor

```dart
Lc3Decoder(int frameDurationUs, int sampleRateHz)
```

- **`frameDurationUs`** - Frame duration in microseconds (e.g., `10000` for 10ms)
- **`sampleRateHz`** - Sample rate in Hertz (e.g., `16000`, `48000`)

**Supported frame durations**: 7500μs (7.5ms) or 10000μs (10ms)  
**Supported sample rates**: 8000, 16000, 24000, 32000, 48000 Hz

#### Methods

##### `decode(Uint8List inputFrame) → Uint8List`

Decodes a single LC3 frame to PCM samples.

- **Parameters**: `inputFrame` - Compressed LC3 frame data
- **Returns**: Raw PCM bytes (16-bit signed integers, little-endian)

##### `dispose()`

Releases native memory. **Must be called** when the decoder is no longer needed.

#### Static Methods

##### `calcFrameBytes(int frameDurationUs, int bitrate) → int`

Calculates the frame size in bytes for given parameters.

- **Parameters**:
  - `frameDurationUs` - Frame duration in microseconds
  - `bitrate` - Bitrate in bits per second
- **Returns**: Frame size in bytes

## Example Application

The package includes a full-featured example app with:

- 📂 File picker for selecting LC3 files
- 🔄 Real-time decoding with progress tracking
- 💾 Export decoded PCM files
- 📊 Performance metrics (decode time, frame count)

### Running the Example

```bash
cd example
flutter run
```

## LC3 File Format

The decoder expects frames in the following format:

- **Frame Header** (2 bytes): Frame size (little-endian)
- **Frame Data** (variable): Compressed LC3 data

For files with headers (18-byte LC3 header), parse the header first to extract sample rate, bitrate, and frame duration parameters.

## Performance

The decoder leverages native C code for optimal performance:

- **Decoding Speed**: ~130,000 frames in 800ms (example benchmark)
- **Memory Efficient**: Minimal allocation overhead
- **Low Latency**: Suitable for real-time applications

## Credits

This package uses the official [liblc3](https://github.com/google/liblc3) implementation by Google.
