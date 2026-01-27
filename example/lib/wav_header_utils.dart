import 'dart:typed_data';

/// Utility class for creating WAV file headers and converting PCM data to WAV format.
class WavHeaderUtils {
  /// Adds a WAV header to raw PCM bytes.
  ///
  /// Parameters:
  /// - [pcmBytes]: Raw PCM audio data
  /// - [sampleRate]: Sample rate in Hz (e.g., 44100, 48000)
  /// - [channels]: Number of audio channels (1 for mono, 2 for stereo)
  /// - [bitDepth]: Bits per sample (typically 16 or 24)
  ///
  /// Returns a [Uint8List] containing the complete WAV file (header + PCM data).
  static Uint8List addWavHeader({
    required Uint8List pcmBytes,
    required int sampleRate,
    required int channels,
    required int bitDepth,
  }) {
    final byteRate = sampleRate * channels * bitDepth ~/ 8;
    final blockAlign = channels * bitDepth ~/ 8;
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;

    final header = BytesBuilder();

    // RIFF chunk
    header.add('RIFF'.codeUnits);
    header.add(_littleEndianBytes(chunkSize, 4));
    header.add('WAVE'.codeUnits);

    // fmt chunk
    header.add('fmt '.codeUnits);
    header.add(_littleEndianBytes(16, 4)); // Subchunk1Size (16 for PCM)
    header.add(_littleEndianBytes(1, 2)); // AudioFormat (1 for PCM)
    header.add(_littleEndianBytes(channels, 2));
    header.add(_littleEndianBytes(sampleRate, 4));
    header.add(_littleEndianBytes(byteRate, 4));
    header.add(_littleEndianBytes(blockAlign, 2));
    header.add(_littleEndianBytes(bitDepth, 2));

    // data chunk
    header.add('data'.codeUnits);
    header.add(_littleEndianBytes(dataSize, 4));
    header.add(pcmBytes);

    return header.toBytes();
  }

  /// Converts an integer value to little-endian bytes.
  static List<int> _littleEndianBytes(int value, int bytes) {
    var list = <int>[];
    for (var i = 0; i < bytes; i++) {
      list.add((value >> (8 * i)) & 0xFF);
    }
    return list;
  }
}
