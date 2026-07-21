// Independent validation against real-world tooling instead of this
// package's own reader: skips instead of failing when the tool isn't
// installed on the machine running the tests (dev-machine only, not CI).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc3_decoder/lc3_to_ogg_transcoder.dart';

const String _testAssetPath = 'example/assets/test.lc3';

bool _toolAvailable(String executable, List<String> versionArgs) {
  try {
    final result = Process.runSync(executable, versionArgs);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffprobeAvailable = _toolAvailable('ffprobe', ['-version']);
  final opusdecAvailable = _toolAvailable('opusdec', ['--version']);

  late Directory tempDir;
  late File outputFile;
  late int expectedNsamples;
  late int expectedSampleRateHz;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('opus_interop_test');
    outputFile = File('${tempDir.path}/interop.ogg');

    final bytes = await File(_testAssetPath).readAsBytes();
    final bd = bytes.buffer.asByteData(bytes.offsetInBytes, 18);
    expectedSampleRateHz = bd.getUint16(4, Endian.little) * 100;
    expectedNsamples = bd.getUint16(14, Endian.little) | (bd.getUint16(16, Endian.little) << 16);

    final t = Lc3ToOggTranscoder(outputFile.path);
    t.feed(bytes);
    await t.finish();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'ffprobe reports mono/48kHz Opus and the expected duration',
    () async {
      final expectedDurationS = expectedNsamples / expectedSampleRateHz;

      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'stream=codec_name,channels,sample_rate:format=duration',
        '-of',
        'json',
        outputFile.path,
      ]);
      expect(result.exitCode, 0, reason: 'ffprobe stderr: ${result.stderr}');

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final stream = (json['streams'] as List).single as Map<String, dynamic>;
      expect(stream['codec_name'], 'opus');
      expect(stream['channels'], 1);
      // Ogg Opus always decodes at a fixed 48 kHz container rate regardless
      // of the original input rate.
      expect(int.parse(stream['sample_rate'] as String), 48000);

      final reportedDurationS = double.parse((json['format'] as Map<String, dynamic>)['duration'] as String);
      expect(reportedDurationS, closeTo(expectedDurationS, 0.05));
    },
    skip: ffprobeAvailable ? false : 'ffprobe not found on PATH (dev-machine interop check only)',
  );

  test(
    'opusdec decodes the file to PCM of the expected sample count',
    () async {
      final wavPath = '${tempDir.path}/interop.wav';
      final result = await Process.run('opusdec', [outputFile.path, wavPath]);
      expect(result.exitCode, 0, reason: 'opusdec stderr: ${result.stderr}');

      final wavBytes = await File(wavPath).readAsBytes();
      // 44-byte canonical WAV header + 16-bit mono PCM data.
      final pcmBytes = wavBytes.length - 44;
      final decodedSamples = pcmBytes ~/ 2;
      expect(decodedSamples, expectedNsamples);
    },
    skip: opusdecAvailable ? false : 'opusdec not found on PATH (dev-machine interop check only)',
  );
}
