// Build-spike gate: proves the vendored libopus + libogg + libopusenc
// sources actually compile, link and run through this package's native
// asset, by round-tripping silence through the raw FFI bindings (no Dart
// wrapper involved yet -- that lives in Lc3ToOggTranscoder).
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc3_decoder/lc3_decoder_bindings_generated.dart';
import 'package:lc3_decoder/src/native_library.dart';

void main() {
  test('ope_encoder_create_file -> write -> drain produces a playable Ogg Opus file', () async {
    final bindings = nativeBindings;
    final tempDir = await Directory.systemTemp.createTemp('opus_build_smoke');
    final outFile = File('${tempDir.path}/smoke.ogg');

    final pathPtr = outFile.path.toNativeUtf8();
    final errorPtr = calloc<ffi.Int>();
    final comments = bindings.ope_comments_create();

    try {
      final enc = bindings.ope_encoder_create_file(pathPtr.cast(), comments, 16000, 1, 0, errorPtr);
      expect(errorPtr.value, OPE_OK, reason: 'ope_encoder_create_file error code');
      expect(enc, isNot(equals(ffi.nullptr)));

      expect(bindings.shim_ope_encoder_ctl_set_application(enc, OPUS_APPLICATION_VOIP), OPUS_OK);
      expect(bindings.shim_ope_encoder_ctl_set_bitrate(enc, 32000), OPUS_OK);
      expect(bindings.shim_ope_encoder_ctl_set_signal(enc, OPUS_SIGNAL_VOICE), OPUS_OK);
      expect(bindings.shim_ope_encoder_ctl_set_vbr(enc, 1), OPUS_OK);

      // One second of silence, fed in 320-sample (20 ms @16 kHz) chunks --
      // the same shape the real transcoder will use, minus the LC3 decode.
      const totalSamples = 16000;
      const chunkSamples = 320;
      final pcm = calloc<ffi.Short>(chunkSamples);
      for (var i = 0; i < chunkSamples; i++) {
        pcm[i] = 0;
      }
      try {
        var written = 0;
        while (written < totalSamples) {
          final n = (totalSamples - written) < chunkSamples ? (totalSamples - written) : chunkSamples;
          final ret = bindings.ope_encoder_write(enc, pcm, n);
          expect(ret, OPE_OK, reason: 'ope_encoder_write at sample $written');
          written += n;
        }
      } finally {
        calloc.free(pcm);
      }

      expect(bindings.ope_encoder_drain(enc), OPE_OK);
      bindings.ope_encoder_destroy(enc);
    } finally {
      bindings.ope_comments_destroy(comments);
      calloc.free(pathPtr);
      calloc.free(errorPtr);
    }

    expect(outFile.existsSync(), isTrue);
    final bytes = await outFile.readAsBytes();
    expect(bytes.length, greaterThan(0));

    // Structural sanity: a well-formed Ogg stream starts with a "OggS"
    // capture pattern page header.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'OggS');

    await tempDir.delete(recursive: true);
  });
}
