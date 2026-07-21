import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'lc3_decoder.dart';
import 'lc3_decoder_bindings_generated.dart';
import 'src/native_library.dart';

const int _lc3HeaderBytes = 18;

// Firmware always emits ~40-byte 32kbps/10ms frames; this is a generous
// sanity ceiling to reject a corrupt/malicious length prefix outright
// instead of buffering forever waiting for bytes that will never arrive.
const int _maxReasonableFrameBytes = 4096;

/// Streams a container of LC3 frames (18-byte header + `[len u16][frame]...`,
/// see the device's file format) straight into an Ogg Opus file on disk,
/// decoding each frame to PCM and handing it to libopusenc as it arrives.
///
/// Usage:
/// ```dart
/// final t = Lc3ToOggTranscoder(outputPath);
/// t.feed(chunkBytes); // any byte window of the LC3 file, called repeatedly
/// await t.finish();   // drains + closes the output file
/// ```
/// On any error, call [abort] to release native resources and delete the
/// partial output file; [abort] is safe to call more than once.
class Lc3ToOggTranscoder {
  /// Path of the Ogg Opus file this transcoder writes.
  final String outputPath;

  /// Creates a transcoder targeting [outputPath]. Nothing touches the
  /// filesystem until the first [feed] completes the LC3 header -- that's
  /// when the output file and the native encoder get created, since the
  /// header carries the sample rate they need.
  Lc3ToOggTranscoder(this.outputPath);

  ffi.Pointer<OggOpusEnc>? _enc;
  ffi.Pointer<OggOpusComments>? _comments;
  Lc3Decoder? _lc3Decoder;
  // Allocated as Int16 (a fixed-size type ffi's Pointer.asTypedList extension
  // supports) and cast to the ABI-specific opus_int16 (Short) only at the
  // ope_encoder_write call site; the two are the same 16-bit width on every
  // platform this package targets.
  ffi.Pointer<ffi.Int16>? _pcmScratch;
  int _pcmScratchCapacity = 0;

  Uint8List _pending = Uint8List(0);
  bool _headerParsed = false;
  bool _finished = false;

  int _sampleRateHz = 0;
  int _frameDurationUs = 0;
  int _nsamples = 0;
  int _fedSamples = 0;

  /// Feeds an arbitrary byte window of the LC3 file. Windows don't need to
  /// align with the header or with frame boundaries -- any leftover partial
  /// header/frame bytes are buffered and completed by a later call.
  void feed(Uint8List chunk) {
    if (_finished) throw StateError('feed() called after finish()/abort()');

    _pending = _append(_pending, chunk);

    if (!_headerParsed) {
      if (_pending.length < _lc3HeaderBytes) return;
      _parseHeaderAndInit();
    }

    _drainCompleteFrames();
  }

  void _parseHeaderAndInit() {
    final bd = _pending.buffer.asByteData(_pending.offsetInBytes, _lc3HeaderBytes);
    // Offset 0: file_id (informational only, mismatches are tolerated
    // elsewhere in this codebase and carry no decoding consequence).
    // Offset 2: header_size, always 18 for this container version -- not
    // used to size the parse, matching the existing conversion code.
    final srate100Hz = bd.getUint16(4, Endian.little);
    final bitrate100Bps = bd.getUint16(6, Endian.little);
    final channels = bd.getUint16(8, Endian.little);
    final frame10Us = bd.getUint16(10, Endian.little);
    // Offset 12: RFU.
    final nsamplesLo = bd.getUint16(14, Endian.little);
    final nsamplesHi = bd.getUint16(16, Endian.little);

    if (channels != 1) {
      throw FormatException('Unsupported channel count in LC3 header: $channels (only mono is supported)');
    }
    if (srate100Hz == 0) {
      throw const FormatException('LC3 header declares a zero sample rate');
    }
    if (frame10Us == 0) {
      throw const FormatException('LC3 header declares a zero frame duration');
    }

    _sampleRateHz = srate100Hz * 100;
    _frameDurationUs = frame10Us * 10;
    _nsamples = nsamplesLo | (nsamplesHi << 16);

    // Bitrate isn't otherwise used by decoding (LC3 frames carry their own
    // length), but a zero value alongside everything else would signal a
    // corrupt header just as clearly.
    if (bitrate100Bps == 0) {
      throw const FormatException('LC3 header declares a zero bitrate');
    }

    _lc3Decoder = Lc3Decoder(_frameDurationUs, _sampleRateHz);

    final pathPtr = outputPath.toNativeUtf8();
    final errorPtr = calloc<ffi.Int>();
    try {
      _comments = nativeBindings.ope_comments_create();
      final enc = nativeBindings.ope_encoder_create_file(pathPtr.cast(), _comments!, _sampleRateHz, 1, 0, errorPtr);
      if (enc == ffi.nullptr) {
        throw StateError('ope_encoder_create_file failed with error code ${errorPtr.value}');
      }
      _enc = enc;
    } finally {
      calloc.free(pathPtr);
      calloc.free(errorPtr);
    }

    nativeBindings.shim_ope_encoder_ctl_set_application(_enc!, OPUS_APPLICATION_VOIP);
    // ponytail: fixed voice-optimized settings, no configuration surface --
    // revisit only if listening/transcription quality shows a reason to.
    nativeBindings.shim_ope_encoder_ctl_set_bitrate(_enc!, 32000);
    nativeBindings.shim_ope_encoder_ctl_set_signal(_enc!, OPUS_SIGNAL_VOICE);
    nativeBindings.shim_ope_encoder_ctl_set_vbr(_enc!, 1);

    _pending = _pending.sublist(_lc3HeaderBytes);
    _headerParsed = true;
  }

  void _drainCompleteFrames() {
    var offset = 0;
    while (true) {
      if (offset + 2 > _pending.length) break;
      final bd = _pending.buffer.asByteData(_pending.offsetInBytes);
      final frameLen = bd.getUint16(offset, Endian.little);

      if (frameLen == 0) {
        throw const FormatException('LC3 frame with zero length');
      }
      if (frameLen > _maxReasonableFrameBytes) {
        throw FormatException('LC3 frame length $frameLen exceeds sanity limit');
      }
      if (offset + 2 + frameLen > _pending.length) {
        break; // wait for the rest of this frame
      }

      if (_fedSamples >= _nsamples) {
        throw const FormatException('LC3 data continues after the header-declared sample count was reached');
      }

      final frameBytes = Uint8List.view(_pending.buffer, _pending.offsetInBytes + offset + 2, frameLen);
      offset += 2 + frameLen;

      final pcmBytes = _lc3Decoder!.decode(frameBytes);
      final samplesDecoded = pcmBytes.length ~/ 2;
      final remaining = _nsamples - _fedSamples;
      final samplesToFeed = samplesDecoded < remaining ? samplesDecoded : remaining;

      _writeSamples(pcmBytes, samplesToFeed);
      _fedSamples += samplesToFeed;
    }

    _pending = offset == 0 ? _pending : _pending.sublist(offset);
  }

  void _writeSamples(Uint8List pcmBytes, int sampleCount) {
    if (sampleCount <= 0) return;
    if (_pcmScratch == null || _pcmScratchCapacity < sampleCount) {
      if (_pcmScratch != null) calloc.free(_pcmScratch!);
      _pcmScratch = calloc<ffi.Int16>(sampleCount);
      _pcmScratchCapacity = sampleCount;
    }
    final scratchView = _pcmScratch!.asTypedList(sampleCount);
    final pcmSamples = pcmBytes.buffer.asInt16List(pcmBytes.offsetInBytes, sampleCount);
    scratchView.setAll(0, pcmSamples);

    final ret = nativeBindings.ope_encoder_write(_enc!, _pcmScratch!.cast<ffi.Short>(), sampleCount);
    if (ret != OPE_OK) {
      throw StateError('ope_encoder_write failed with error code $ret');
    }
  }

  /// Finalizes the Ogg Opus file: validates that the full sample count
  /// declared in the header was received, drains libopusenc's internal
  /// buffering (end-trimming, lookahead, final page) and closes the file.
  /// On any failure this calls [abort] before rethrowing.
  Future<void> finish() async {
    try {
      if (!_headerParsed) {
        throw const FormatException('LC3 stream ended before a complete header was received');
      }
      if (_fedSamples < _nsamples) {
        throw FormatException('LC3 stream ended after $_fedSamples of $_nsamples declared samples');
      }
      if (_pending.isNotEmpty) {
        throw const FormatException('Trailing bytes found after the header-declared sample count was reached');
      }

      final drainRet = nativeBindings.ope_encoder_drain(_enc!);
      if (drainRet != OPE_OK) {
        throw StateError('ope_encoder_drain failed with error code $drainRet');
      }

      nativeBindings.ope_encoder_destroy(_enc!);
      _enc = null;
      _releaseNonEncoderResources();
      _finished = true;
    } catch (_) {
      abort();
      rethrow;
    }
  }

  /// Releases native resources and deletes the (possibly partial) output
  /// file. Safe to call multiple times and safe to call whether or not
  /// [feed]/[finish] ever ran. Never throws -- callers use this from error
  /// handlers, where a cleanup failure must not shadow the original error
  /// or crash an otherwise-recovering flow.
  void abort() {
    try {
      if (_enc != null) {
        nativeBindings.ope_encoder_destroy(_enc!);
        _enc = null;
      }
      _releaseNonEncoderResources();
      _finished = true;

      final file = File(outputPath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort: the caller is already handling a failure (or this is a
      // redundant abort); an orphaned file here gets swept by the caller's
      // own cleanup pass.
    }
  }

  void _releaseNonEncoderResources() {
    if (_comments != null) {
      nativeBindings.ope_comments_destroy(_comments!);
      _comments = null;
    }
    _lc3Decoder?.dispose();
    _lc3Decoder = null;
    if (_pcmScratch != null) {
      calloc.free(_pcmScratch!);
      _pcmScratch = null;
      _pcmScratchCapacity = 0;
    }
  }

  static Uint8List _append(Uint8List existing, Uint8List more) {
    if (existing.isEmpty) return more;
    if (more.isEmpty) return existing;
    final combined = Uint8List(existing.length + more.length);
    combined.setAll(0, existing);
    combined.setAll(existing.length, more);
    return combined;
  }
}
