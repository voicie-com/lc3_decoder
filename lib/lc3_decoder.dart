import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'lc3_decoder_bindings_generated.dart';

const String _libName = 'lc3';

/// The dynamic library in which the symbols for [Lc3DecoderBindings] can be found.
final ffi.DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      // Try loading as a dynamic framework (module)
      return ffi.DynamicLibrary.open('lc3_decoder.framework/lc3_decoder');
    } catch (_) {
      // Fallback to process symbols (static linking)
      return ffi.DynamicLibrary.process();
    }
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
    // 1. Calculate the required memory size for the decoder.
    final int size = _bindings.lc3_decoder_size(
      _frameDurationUs,
      _sampleRateHz,
    );
    if (size == 0) {
      throw Exception(
        'Failed to calculate LC3 decoder size. Invalid parameters?',
      );
    }

    // 2. Allocate memory for the decoder state.
    _decoderMemory = calloc<ffi.Uint8>(size).cast<ffi.Void>();

    // 3. Setup the decoder.
    // We assume input and output sample rates are the same for this simple example.
    _decoder = _bindings.lc3_setup_decoder(
      _frameDurationUs,
      _sampleRateHz,
      0, // 0 defaults to sr_hz for PCM output
      _decoderMemory,
    );

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

    // Use malloc for temporary buffers if needed, or pass pointers directly if possible.
    // However, inputFrame is a Dart object. We need to copy it to C memory or use a typed data pointer.
    // For simplicity and safety, we'll allocate C memory.
    final ffi.Pointer<ffi.Uint8> inputPtr = calloc<ffi.Uint8>(inputSize);
    final Uint8List inputView = inputPtr.asTypedList(inputSize);
    inputView.setAll(0, inputFrame);

    // Calculate output size.
    // We need to know how many samples effectively.
    // lc3_frame_samples returns samples per frame.
    final int samplesPerFrame = _bindings.lc3_frame_samples(
      _frameDurationUs,
      _sampleRateHz,
    );
    if (samplesPerFrame == -1) {
      calloc.free(inputPtr);
      throw Exception('Failed to calculate samples per frame.');
    }

    // We assume 16-bit PCM for this example (S16).
    // S16 = 2 bytes per sample.
    final int outputSizeBytes = samplesPerFrame * 2;
    final ffi.Pointer<ffi.Void> outputPtr = calloc<ffi.Uint8>(
      outputSizeBytes,
    ).cast<ffi.Void>();

    try {
      final int result = _bindings.lc3_decode(
        _decoder,
        inputPtr.cast<ffi.Void>(), // input bitstream
        inputSize, // size in bytes
        lc3_pcm_format.LC3_PCM_FORMAT_S16, // PCM format
        outputPtr, // output buffer
        1, // stride (1 = interleaved/contiguous for 1 channel)
      );

      if (result != 0 && result != 1) {
        // 0 is success, 1 is PLC operated (still valid output)
        throw Exception('LC3 decode failed with error code: $result');
      }

      // Copy result back to Dart
      final Uint8List outputBytes = Uint8List(outputSizeBytes);
      // We cast to Uint8 pointer to copy bytes.
      final ffi.Pointer<ffi.Uint8> outputUint8Ptr = outputPtr.cast<ffi.Uint8>();
      final Uint8List nativeOutputView = outputUint8Ptr.asTypedList(
        outputSizeBytes,
      );
      outputBytes.setAll(0, nativeOutputView);

      return outputBytes;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  void dispose() {
    calloc.free(_decoderMemory);
  }
}
