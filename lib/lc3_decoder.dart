import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'lc3_decoder_bindings_generated.dart';

const String _libName = 'lc3_decoder';

/// The dynamic library in which the symbols for [Lc3DecoderBindings] can be found.
final ffi.DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    // On iOS, native assets bundle the library as a framework in the app's Frameworks folder.
    // We need to load it explicitly by its framework path.
    return ffi.DynamicLibrary.open('lc3_decoder.framework/lc3_decoder');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final Lc3DecoderBindings _bindings = Lc3DecoderBindings(_dylib);

/// A wrapper for the LC3 (Low Complexity Communication Codec) decoder.
///
/// This class provides an interface to decode LC3-compressed audio frames
/// into PCM samples. LC3 is a low-latency audio codec designed for wireless
/// audio applications.
///
/// Example usage:
/// ```dart
/// final decoder = Lc3Decoder(10000, 48000); // 10ms frames at 48kHz
/// final pcmData = decoder.decode(compressedFrame);
/// decoder.dispose(); // Don't forget to clean up when done
/// ```
class Lc3Decoder {
  late final ffi.Pointer<ffi.Void> _decoderMemory;
  late final lc3_decoder_t _decoder; // Typedef for ffi.Pointer<lc3_decoder>
  final int _frameDurationUs;
  final int _sampleRateHz;

  /// Calculates the frame size in bytes for a given duration and bitrate.
  static int calcFrameBytes(int frameDurationUs, int bitrate) {
    return _bindings.lc3_frame_bytes(frameDurationUs, bitrate);
  }

  /// Creates a new LC3 decoder.
  ///
  /// [frameDurationUs] is the frame duration in microseconds (e.g., 10000 for 10ms).
  /// [sampleRateHz] is the sample rate in Hertz (e.g., 16000, 48000).
  Lc3Decoder(this._frameDurationUs, this._sampleRateHz) {
    _init();
  }

  void _init() {
    final int size = _bindings.lc3_decoder_size(_frameDurationUs, _sampleRateHz);
    if (size == 0) {
      throw Exception('Failed to calculate LC3 decoder size. Invalid parameters?');
    }

    _decoderMemory = calloc<ffi.Uint8>(size).cast<ffi.Void>();

    _decoder = _bindings.lc3_setup_decoder(_frameDurationUs, _sampleRateHz, 0, _decoderMemory);

    if (_decoder == ffi.nullptr) {
      calloc.free(_decoderMemory);
      throw Exception('Failed to setup LC3 decoder.');
    }
  }

  /// Decodes a simplified LC3 frame to PCM samples.
  ///
  /// [inputFrame] contains the compressed LC3 bytes.
  /// Returns a Uint8List containing the raw PCM bytes (16-bit signed integers).
  Uint8List decode(Uint8List inputFrame) {
    final int inputSize = inputFrame.length;
    final ffi.Pointer<ffi.Uint8> inputPtr = calloc<ffi.Uint8>(inputSize);
    final Uint8List inputView = inputPtr.asTypedList(inputSize);
    inputView.setAll(0, inputFrame);

    final int samplesPerFrame = _bindings.lc3_frame_samples(_frameDurationUs, _sampleRateHz);
    if (samplesPerFrame == -1) {
      calloc.free(inputPtr);
      throw Exception('Failed to calculate samples per frame.');
    }

    final int outputSizeBytes = samplesPerFrame * 2;
    final ffi.Pointer<ffi.Void> outputPtr = calloc<ffi.Uint8>(outputSizeBytes).cast<ffi.Void>();

    try {
      final int result = _bindings.lc3_decode(
        _decoder,
        inputPtr.cast<ffi.Void>(),
        inputSize,
        lc3_pcm_format.LC3_PCM_FORMAT_S16,
        outputPtr,
        1,
      );

      if (result != 0 && result != 1) {
        throw Exception('LC3 decode failed with error code: $result');
      }

      final Uint8List outputBytes = Uint8List(outputSizeBytes);
      final ffi.Pointer<ffi.Uint8> outputUint8Ptr = outputPtr.cast<ffi.Uint8>();
      final Uint8List nativeOutputView = outputUint8Ptr.asTypedList(outputSizeBytes);
      outputBytes.setAll(0, nativeOutputView);

      return outputBytes;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Releases the native memory allocated for the decoder.
  ///
  /// Call this method when you're done using the decoder to free up resources.
  /// After calling dispose(), this decoder instance should not be used again.
  void dispose() {
    calloc.free(_decoderMemory);
  }
}
