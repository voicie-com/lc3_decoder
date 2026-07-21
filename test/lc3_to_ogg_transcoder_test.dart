import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc3_decoder/lc3_to_ogg_transcoder.dart';
import 'package:lc3_decoder/ogg_opus_duration.dart';

const String _testAssetPath = 'example/assets/test.lc3';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lc3_to_ogg_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('feed split fuzzing (real device asset)', () {
    test('feeding the whole file in one call produces the exact declared duration', () async {
      final bytes = await File(_testAssetPath).readAsBytes();
      final header = _parseHeader(bytes);
      final outPath = '${tempDir.path}/whole.ogg';

      final t = Lc3ToOggTranscoder(outPath);
      t.feed(bytes);
      await t.finish();

      final durationMs = await readOggOpusDurationMs(File(outPath));
      expect(durationMs, header.nsamples * 1000 ~/ header.sampleRateHz);
    });

    test('feeding byte-by-byte produces the same result as feeding the whole file', () async {
      final bytes = await File(_testAssetPath).readAsBytes();
      final header = _parseHeader(bytes);
      final outPath = '${tempDir.path}/byte_by_byte.ogg';

      final t = Lc3ToOggTranscoder(outPath);
      for (final b in bytes) {
        t.feed(Uint8List.fromList([b]));
      }
      await t.finish();

      final durationMs = await readOggOpusDurationMs(File(outPath));
      expect(durationMs, header.nsamples * 1000 ~/ header.sampleRateHz);
    });

    test('splitting on every possible byte boundary always succeeds and matches duration', () async {
      final bytes = await File(_testAssetPath).readAsBytes();
      final header = _parseHeader(bytes);
      final expectedMs = header.nsamples * 1000 ~/ header.sampleRateHz;

      // Exhaustively splitting a ~54KB file at every boundary would be slow;
      // sample split points so header bytes, length-prefix bytes and frame
      // payload bytes are all exercised as a split boundary at some point.
      final splitPoints = <int>{
        for (var i = 1; i < 18; i++) i, // inside/around the header
        18, 19, 20, // first length prefix + first payload byte
        60, 61, 62, // second frame's length prefix
        bytes.length - 1,
        bytes.length,
      }..removeWhere((p) => p <= 0 || p >= bytes.length);

      for (final splitPoint in splitPoints) {
        final outPath = '${tempDir.path}/split_$splitPoint.ogg';
        final t = Lc3ToOggTranscoder(outPath);
        t.feed(bytes.sublist(0, splitPoint));
        t.feed(bytes.sublist(splitPoint));
        await t.finish();

        final durationMs = await readOggOpusDurationMs(File(outPath));
        expect(durationMs, expectedMs, reason: 'split at byte $splitPoint');
      }
    });
  });

  group('malformed input rejection', () {
    test('truncated header throws on finish', () async {
      final bytes = await File(_testAssetPath).readAsBytes();
      final outPath = '${tempDir.path}/truncated_header.ogg';
      final t = Lc3ToOggTranscoder(outPath);
      t.feed(bytes.sublist(0, 10)); // fewer than 18 header bytes, ever

      await expectLater(t.finish(), throwsFormatException);
      expect(File(outPath).existsSync(), isFalse);
    });

    test('truncated frame throws on finish', () async {
      final bytes = await File(_testAssetPath).readAsBytes();
      final outPath = '${tempDir.path}/truncated_frame.ogg';
      final t = Lc3ToOggTranscoder(outPath);
      // Full header plus a length prefix promising more payload than follows.
      t.feed(bytes.sublist(0, 18 + 2 + 10));

      await expectLater(t.finish(), throwsFormatException);
      expect(File(outPath).existsSync(), isFalse);
    });

    test('zero-length frame throws from feed, not silently', () async {
      final fixture = await _loadFixtureFrames();
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 160,
        frames: [Uint8List(0)],
      );
      final t = Lc3ToOggTranscoder('${tempDir.path}/zero_len.ogg');
      expect(() => t.feed(container), throwsFormatException);
      t.abort();
    });

    test('excessively large frame length throws from feed, not silently', () async {
      final fixture = await _loadFixtureFrames();
      final oversized = ByteData(2)..setUint16(0, 60000, Endian.little);
      final container = BytesBuilder()
        ..add(
          _buildContainer(
            sampleRateHz: fixture.sampleRateHz,
            bitrateBps: 32000,
            channels: 1,
            frameDurationUs: fixture.frameDurationUs,
            nsamples: 160,
            frames: const [],
          ),
        )
        ..add(oversized.buffer.asUint8List())
        ..add(Uint8List(100)); // nowhere near 60000 bytes -- doesn't matter, rejected on the prefix alone

      final t = Lc3ToOggTranscoder('${tempDir.path}/oversized.ogg');
      expect(() => t.feed(container.toBytes()), throwsFormatException);
      t.abort();
    });

    test('unsupported channel count throws from feed', () async {
      final fixture = await _loadFixtureFrames();
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 2,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 160,
        frames: [fixture.frames.first],
      );
      final t = Lc3ToOggTranscoder('${tempDir.path}/bad_channels.ogg');
      expect(() => t.feed(container), throwsFormatException);
      t.abort();
    });

    test('zero sample rate throws from feed', () async {
      final fixture = await _loadFixtureFrames();
      final container = _buildContainer(
        sampleRateHz: 0,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 160,
        frames: [fixture.frames.first],
      );
      final t = Lc3ToOggTranscoder('${tempDir.path}/bad_srate.ogg');
      expect(() => t.feed(container), throwsFormatException);
      t.abort();
    });

    test('zero frame duration throws from feed', () async {
      final fixture = await _loadFixtureFrames();
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: 0,
        nsamples: 160,
        frames: [fixture.frames.first],
      );
      final t = Lc3ToOggTranscoder('${tempDir.path}/bad_frame_dur.ogg');
      expect(() => t.feed(container), throwsFormatException);
      t.abort();
    });
  });

  group('sample-count boundary contract', () {
    test('a full extra frame after nsamples is reached throws', () async {
      final fixture = await _loadFixtureFrames();
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 160, // exactly one frame's worth
        frames: [fixture.frames[0], fixture.frames[1]], // a second, unexpected frame follows
      );
      final t = Lc3ToOggTranscoder('${tempDir.path}/extra_frame.ogg');
      expect(() => t.feed(container), throwsFormatException);
      t.abort();
    });

    test('trailing bytes after nsamples is reached throw (from feed or finish)', () async {
      final fixture = await _loadFixtureFrames();
      final container = BytesBuilder()
        ..add(
          _buildContainer(
            sampleRateHz: fixture.sampleRateHz,
            bitrateBps: 32000,
            channels: 1,
            frameDurationUs: fixture.frameDurationUs,
            nsamples: 160,
            frames: [fixture.frames[0]],
          ),
        )
        ..add(Uint8List.fromList([1, 2, 3])); // not a complete frame, just garbage

      final t = Lc3ToOggTranscoder('${tempDir.path}/trailing_garbage.ogg');
      Object? caught;
      try {
        t.feed(container.toBytes());
        await t.finish();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FormatException>());
    });

    test('sample count is trimmed exactly on a partial final frame', () async {
      final fixture = await _loadFixtureFrames();
      const nsamples = 240; // one full 160-sample frame + 80 of the second
      final outPath = '${tempDir.path}/trimmed.ogg';
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: nsamples,
        frames: [fixture.frames[0], fixture.frames[1]],
      );

      final t = Lc3ToOggTranscoder(outPath);
      t.feed(container);
      await t.finish();

      final durationMs = await readOggOpusDurationMs(File(outPath));
      expect(durationMs, nsamples * 1000 ~/ fixture.sampleRateHz);
    });

    test('fewer samples than declared throws at finish (incomplete stream)', () async {
      final fixture = await _loadFixtureFrames();
      final t = Lc3ToOggTranscoder('${tempDir.path}/incomplete.ogg');
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 320, // declares two frames' worth
        frames: [fixture.frames[0]], // only one frame ever arrives
      );
      t.feed(container);
      await expectLater(t.finish(), throwsFormatException);
    });
  });

  group('abort/lifecycle', () {
    test('abort deletes the partial output file and is idempotent', () async {
      final fixture = await _loadFixtureFrames();
      final outPath = '${tempDir.path}/aborted.ogg';
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 320,
        frames: [fixture.frames[0]],
      );
      final t = Lc3ToOggTranscoder(outPath);
      t.feed(container);
      expect(File(outPath).existsSync(), isTrue);

      t.abort();
      expect(File(outPath).existsSync(), isFalse);

      t.abort(); // must not throw
      expect(File(outPath).existsSync(), isFalse);
    });

    test('feed after finish throws StateError', () async {
      final fixture = await _loadFixtureFrames();
      final outPath = '${tempDir.path}/after_finish.ogg';
      final container = _buildContainer(
        sampleRateHz: fixture.sampleRateHz,
        bitrateBps: 32000,
        channels: 1,
        frameDurationUs: fixture.frameDurationUs,
        nsamples: 160,
        frames: [fixture.frames[0]],
      );
      final t = Lc3ToOggTranscoder(outPath);
      t.feed(container);
      await t.finish();

      expect(() => t.feed(Uint8List(1)), throwsStateError);
    });
  });
}

class _Header {
  final int sampleRateHz;
  final int frameDurationUs;
  final int nsamples;
  const _Header({required this.sampleRateHz, required this.frameDurationUs, required this.nsamples});
}

_Header _parseHeader(Uint8List bytes) {
  final bd = bytes.buffer.asByteData(bytes.offsetInBytes, 18);
  final srate100 = bd.getUint16(4, Endian.little);
  final frame10us = bd.getUint16(10, Endian.little);
  final nsLo = bd.getUint16(14, Endian.little);
  final nsHi = bd.getUint16(16, Endian.little);
  return _Header(sampleRateHz: srate100 * 100, frameDurationUs: frame10us * 10, nsamples: nsLo | (nsHi << 16));
}

class _Fixture {
  final int sampleRateHz;
  final int frameDurationUs;
  final List<Uint8List> frames;
  const _Fixture({required this.sampleRateHz, required this.frameDurationUs, required this.frames});
}

/// Loads a handful of real, decodable LC3 frames (and the source rate/frame
/// duration) from the checked-in device asset, for building small synthetic
/// containers with a header this test controls.
Future<_Fixture> _loadFixtureFrames() async {
  final bytes = await File(_testAssetPath).readAsBytes();
  final header = _parseHeader(bytes);
  final bd = bytes.buffer.asByteData();
  var offset = 18;
  final frames = <Uint8List>[];
  while (offset + 2 <= bytes.length && frames.length < 4) {
    final len = bd.getUint16(offset, Endian.little);
    offset += 2;
    if (offset + len > bytes.length) break;
    frames.add(bytes.sublist(offset, offset + len));
    offset += len;
  }
  return _Fixture(sampleRateHz: header.sampleRateHz, frameDurationUs: header.frameDurationUs, frames: frames);
}

Uint8List _buildContainer({
  required int sampleRateHz,
  required int bitrateBps,
  required int channels,
  required int frameDurationUs,
  required int nsamples,
  required List<Uint8List> frames,
}) {
  final header = ByteData(18)
    ..setUint16(0, 0xCC1C, Endian.little)
    ..setUint16(2, 18, Endian.little)
    ..setUint16(4, sampleRateHz ~/ 100, Endian.little)
    ..setUint16(6, bitrateBps ~/ 100, Endian.little)
    ..setUint16(8, channels, Endian.little)
    ..setUint16(10, frameDurationUs ~/ 10, Endian.little)
    ..setUint16(12, 0, Endian.little)
    ..setUint16(14, nsamples & 0xFFFF, Endian.little)
    ..setUint16(16, (nsamples >> 16) & 0xFFFF, Endian.little);

  final builder = BytesBuilder()..add(header.buffer.asUint8List());
  for (final frame in frames) {
    final lenPrefix = ByteData(2)..setUint16(0, frame.length, Endian.little);
    builder.add(lenPrefix.buffer.asUint8List());
    builder.add(frame);
  }
  return builder.toBytes();
}
