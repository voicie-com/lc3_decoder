import 'dart:io';
import 'dart:typed_data';
import 'package:lc3_decoder/lc3_decoder.dart';

// Constants from C code
const int LC3_FILE_ID = 0xCC1C; // (0x1C | (0xCC << 8))

void main(List<String> args) {
  if (args.length < 2) {
    print('Usage: dart run bin/simple_decoder.dart <input.lc3> <output.pcm>');
    print(
      '\nParses files with the structure: [Header (18 bytes)] [2-byte Length][Frame Data]...',
    );
    return;
  }

  final inputFile = File(args[0]);
  final outputFile = File(args[1]);

  if (!inputFile.existsSync()) {
    print('Input file not found: ${inputFile.path}');
    return;
  }

  try {
    final bytes = inputFile.readAsBytesSync();
    final ByteData bd = bytes.buffer.asByteData();
    int offset = 0;

    // --- Parse Header (18 bytes) ---
    if (bytes.length < 18) {
      throw Exception('File too short to contain header');
    }

    final fileId = bd.getUint16(offset, Endian.little);
    offset += 2;
    if (fileId != LC3_FILE_ID) {
      print(
        'Warning: File ID 0x${fileId.toRadixString(16).toUpperCase()} does not match expected 0x${LC3_FILE_ID.toRadixString(16).toUpperCase()}',
      );
      // We continue anyway, as it might just be a raw file, but this script expects the format described.
    }

    final headerSize = bd.getUint16(offset, Endian.little);
    offset += 2;
    final srate100Hz = bd.getUint16(offset, Endian.little);
    offset += 2;
    final bitrate100Bps = bd.getUint16(offset, Endian.little);
    offset += 2;
    final channels = bd.getUint16(offset, Endian.little);
    offset += 2;
    final frame10Us = bd.getUint16(offset, Endian.little);
    offset += 2;
    // Skip RFU (2), nsamples_low (2), nsamples_high (2)
    offset += 6;

    // Derived parameters
    final sampleRate = srate100Hz * 100;
    final frameDurationUs = frame10Us * 10;
    final bitrate = bitrate100Bps * 100;

    print('--- Header Info ---');
    print('Header Size: $headerSize');
    print('Sample Rate: $sampleRate Hz');
    print('Bitrate: $bitrate bps');
    print('Channels: $channels');
    print('Frame Duration: $frameDurationUs us');
    print('-------------------');

    if (channels != 1) {
      print('Warning: This script assumes 1 channel for simplicity.');
    }

    // --- Initialize Decoder ---
    final decoder = Lc3Decoder(frameDurationUs, sampleRate);
    final outputBuffer = BytesBuilder();
    int frameCount = 0;
    final stopwatch = Stopwatch()..start();

    // --- Decode Frames ---
    // Format: [2 bytes Length] [Data]
    while (offset < bytes.length) {
      if (offset + 2 > bytes.length) break;

      final frameSize = bd.getUint16(offset, Endian.little);
      offset += 2;

      if (offset + frameSize > bytes.length) {
        print('Error: Incomplete frame at end of file.');
        break;
      }

      final frameData = bytes.sublist(offset, offset + frameSize);
      offset += frameSize;

      try {
        final pcm = decoder.decode(frameData);
        outputBuffer.add(pcm);
        frameCount++;
      } catch (e) {
        print('Decode error at frame $frameCount: $e');
        // Depending on requirements, we might want to fill with silence or continue
        break;
      }
    }

    decoder.dispose();
    stopwatch.stop();

    outputFile.writeAsBytesSync(outputBuffer.toBytes());
    print('Decoding complete.');
    print(
      'Processed $frameCount frames in ${stopwatch.elapsedMilliseconds}ms.',
    );
    print('Output written to ${outputFile.path}');
  } catch (e, stack) {
    print('Fatal error: $e');
    print(stack);
  }
}
