import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc3_decoder/ogg_opus_duration.dart';

const int _bosFlag = 0x02;
const int _eosFlag = 0x04;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ogg_opus_duration_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('a well-formed single-stream file returns the exact granule-derived duration', () async {
    final bytes = BytesBuilder()
      ..add(
        _oggPage(
          headerType: _bosFlag,
          granulePosition: 0,
          serialNumber: 1,
          pageSequence: 0,
          payload: _opusHeadPayload(preSkip: 312),
        ),
      )
      ..add(
        _oggPage(
          headerType: _eosFlag,
          granulePosition: 48312,
          serialNumber: 1,
          pageSequence: 1,
          payload: Uint8List.fromList([1, 2, 3]),
        ),
      );

    final file = await _writeFile(tempDir, 'valid.ogg', bytes.toBytes());
    expect(await readOggOpusDurationMs(file), 1000);
  });

  test('a missing EOS page returns null', () async {
    // Only the BOS/ID-header page exists -- the stream was never finalized.
    final bytes = _oggPage(
      headerType: _bosFlag,
      granulePosition: 0,
      serialNumber: 1,
      pageSequence: 0,
      payload: _opusHeadPayload(preSkip: 0),
    );

    final file = await _writeFile(tempDir, 'no_eos.ogg', bytes);
    expect(await readOggOpusDurationMs(file), isNull);
  });

  test('an EOS page belonging to a different serial number returns null', () async {
    final bytes = BytesBuilder()
      ..add(
        _oggPage(
          headerType: _bosFlag,
          granulePosition: 0,
          serialNumber: 1,
          pageSequence: 0,
          payload: _opusHeadPayload(preSkip: 0),
        ),
      )
      ..add(
        _oggPage(
          headerType: _eosFlag,
          granulePosition: 48000,
          serialNumber: 2,
          pageSequence: 1,
          payload: Uint8List.fromList([1]),
        ),
      );

    final file = await _writeFile(tempDir, 'wrong_serial.ogg', bytes.toBytes());
    expect(await readOggOpusDurationMs(file), isNull);
  });

  test('a chained (concatenated) stream returns null instead of the wrong stream\'s duration', () async {
    final bytes = BytesBuilder()
      // Complete first logical stream, serial 1.
      ..add(
        _oggPage(
          headerType: _bosFlag,
          granulePosition: 0,
          serialNumber: 1,
          pageSequence: 0,
          payload: _opusHeadPayload(preSkip: 0),
        ),
      )
      ..add(
        _oggPage(
          headerType: _eosFlag,
          granulePosition: 48000,
          serialNumber: 1,
          pageSequence: 1,
          payload: Uint8List.fromList([1]),
        ),
      )
      // A second logical stream chained on, serial 2.
      ..add(
        _oggPage(
          headerType: _bosFlag,
          granulePosition: 0,
          serialNumber: 2,
          pageSequence: 0,
          payload: _opusHeadPayload(preSkip: 0),
        ),
      )
      ..add(
        _oggPage(
          headerType: _eosFlag,
          granulePosition: 24000,
          serialNumber: 2,
          pageSequence: 1,
          payload: Uint8List.fromList([1]),
        ),
      );

    final file = await _writeFile(tempDir, 'chained.ogg', bytes.toBytes());
    expect(await readOggOpusDurationMs(file), isNull);
  });

  test('a granule position smaller than pre-skip returns null', () async {
    final bytes = BytesBuilder()
      ..add(
        _oggPage(
          headerType: _bosFlag,
          granulePosition: 0,
          serialNumber: 1,
          pageSequence: 0,
          payload: _opusHeadPayload(preSkip: 1000),
        ),
      )
      ..add(
        _oggPage(
          headerType: _eosFlag,
          granulePosition: 500,
          serialNumber: 1,
          pageSequence: 1,
          payload: Uint8List.fromList([1]),
        ),
      );

    final file = await _writeFile(tempDir, 'granule_below_preskip.ogg', bytes.toBytes());
    expect(await readOggOpusDurationMs(file), isNull);
  });

  test('a truncated segment table on the terminal page returns null', () async {
    final bos = _oggPage(
      headerType: _bosFlag,
      granulePosition: 0,
      serialNumber: 1,
      pageSequence: 0,
      payload: _opusHeadPayload(preSkip: 0),
    );
    // A 300-byte payload needs a 2-entry segment table ([255, 45]); cut the
    // page off after only the first entry, so the table itself is
    // incomplete (distinct from a page whose table is intact but whose
    // payload is short).
    final goodEos = _oggPage(
      headerType: _eosFlag,
      granulePosition: 48000,
      serialNumber: 1,
      pageSequence: 1,
      payload: Uint8List(300),
    );
    final truncatedEos = goodEos.sublist(0, 27 + 1);

    final bytes = BytesBuilder()
      ..add(bos)
      ..add(truncatedEos);

    final file = await _writeFile(tempDir, 'truncated_segment_table.ogg', bytes.toBytes());
    expect(await readOggOpusDurationMs(file), isNull);
  });

  test('a completely empty file returns null without throwing', () async {
    final file = await _writeFile(tempDir, 'empty.ogg', Uint8List(0));
    expect(await readOggOpusDurationMs(file), isNull);
  });

  test('a non-Opus (missing OpusHead) first page returns null', () async {
    final bytes = _oggPage(
      headerType: _bosFlag,
      granulePosition: 0,
      serialNumber: 1,
      pageSequence: 0,
      payload: Uint8List.fromList('NotOpusHead'.codeUnits),
    );

    final file = await _writeFile(tempDir, 'not_opus.ogg', bytes);
    expect(await readOggOpusDurationMs(file), isNull);
  });
}

Future<File> _writeFile(Directory dir, String name, Uint8List bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Uint8List _opusHeadPayload({required int preSkip}) {
  final b = BytesBuilder()..add('OpusHead'.codeUnits);
  b.addByte(1); // version
  b.addByte(1); // channel count
  b.add((ByteData(2)..setUint16(0, preSkip, Endian.little)).buffer.asUint8List());
  b.add((ByteData(4)..setUint32(0, 16000, Endian.little)).buffer.asUint8List()); // input sample rate
  b.add(Uint8List(2)); // output gain
  b.addByte(0); // channel mapping family
  return b.toBytes();
}

/// Builds one raw Ogg page. The checksum field is left as zero -- this
/// reader never validates it, matching a real (if imperfect) fail-safe
/// implementation that only needs the header fields to extract duration.
Uint8List _oggPage({
  required int headerType,
  required int granulePosition,
  required int serialNumber,
  required int pageSequence,
  required Uint8List payload,
}) {
  final segments = <int>[];
  var remaining = payload.length;
  while (remaining >= 255) {
    segments.add(255);
    remaining -= 255;
  }
  segments.add(remaining);

  final b = BytesBuilder()..add([0x4F, 0x67, 0x67, 0x53]); // "OggS"
  b.addByte(0); // version
  b.addByte(headerType);
  b.add((ByteData(8)..setInt64(0, granulePosition, Endian.little)).buffer.asUint8List());
  b.add((ByteData(4)..setUint32(0, serialNumber, Endian.little)).buffer.asUint8List());
  b.add((ByteData(4)..setUint32(0, pageSequence, Endian.little)).buffer.asUint8List());
  b.add(Uint8List(4)); // checksum (unchecked)
  b.addByte(segments.length);
  b.add(Uint8List.fromList(segments));
  b.add(payload);
  return b.toBytes();
}
