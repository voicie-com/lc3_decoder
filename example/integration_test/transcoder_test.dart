import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lc3_decoder/lc3_to_ogg_transcoder.dart';
import 'package:lc3_decoder/ogg_opus_duration.dart';
import 'package:path_provider/path_provider.dart';

/// Runs the transcoder inside a real app process, which is the only place the
/// packaged framework layout of the native asset is exercised: the unit tests
/// load the bare dylib a host build leaves behind, and an iOS build only ever
/// proves the library links, never that it loads and runs once bundled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory workDir;
  late Uint8List assetBytes;

  setUp(() async {
    workDir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/transcoder_integration_test',
    );
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);
    assetBytes = (await rootBundle.load('assets/test.lc3')).buffer.asUint8List();
  });

  tearDown(() {
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
  });

  testWidgets('transcodes the bundled asset to Ogg Opus of the declared duration', (_) async {
    final outPath = '${workDir.path}/whole.ogg';

    final transcoder = Lc3ToOggTranscoder(outPath);
    transcoder.feed(assetBytes);
    await transcoder.finish();

    final output = File(outPath);
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), greaterThan(0));

    final header = _parseHeader(assetBytes);
    expect(
      await readOggOpusDurationMs(output),
      header.nsamples * 1000 ~/ header.sampleRateHz,
    );
  });

  testWidgets('chunked feeding produces the same duration as one call', (_) async {
    final outPath = '${workDir.path}/chunked.ogg';

    final transcoder = Lc3ToOggTranscoder(outPath);
    // 512 bytes is the device's BLE chunk size, so this mirrors how the app
    // actually feeds the transcoder during a sync.
    for (var offset = 0; offset < assetBytes.length; offset += 512) {
      final end = (offset + 512).clamp(0, assetBytes.length);
      transcoder.feed(Uint8List.sublistView(assetBytes, offset, end));
    }
    await transcoder.finish();

    final header = _parseHeader(assetBytes);
    expect(
      await readOggOpusDurationMs(File(outPath)),
      header.nsamples * 1000 ~/ header.sampleRateHz,
    );
  });
}

({int sampleRateHz, int nsamples}) _parseHeader(Uint8List bytes) {
  final bd = bytes.buffer.asByteData(bytes.offsetInBytes, 18);
  return (
    sampleRateHz: bd.getUint16(4, Endian.little) * 100,
    nsamples: bd.getUint16(14, Endian.little) | (bd.getUint16(16, Endian.little) << 16),
  );
}
