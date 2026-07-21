import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

// liblc3 decodes the device's raw frames. libopus + libopusenc encode/mux
// the PCM into Ogg Opus in the same native asset, so the whole
// LC3 -> OGG/Opus transcode runs without an extra process hop.
const List<String> _lc3Sources = [
  'src/liblc3/src/attdet.c',
  'src/liblc3/src/bits.c',
  'src/liblc3/src/bwdet.c',
  'src/liblc3/src/energy.c',
  'src/liblc3/src/lc3.c',
  'src/liblc3/src/ltpf.c',
  'src/liblc3/src/mdct.c',
  'src/liblc3/src/plc.c',
  'src/liblc3/src/sns.c',
  'src/liblc3/src/spec.c',
  'src/liblc3/src/tables.c',
  'src/liblc3/src/tns.c',
];

// libopus and libopusenc are each vendored as dozens of small .c
// files (see src/opus/{celt,silk,opus}_sources.mk for the authoritative
// per-file manifest upstream ships). Passing every one of those ~140 files
// as its own cl.exe argument blows past cmd.exe's ~8k command-line length
// once combined with this repo's absolute path -- MSVC builds go through a
// `cmd.exe /c` wrapper (needed to carry the resolved MSVC environment), and
// that wrapper has a much lower limit than the ~32k CreateProcess itself
// allows. Groups without cross-file quirks are instead a single "unity
// build" file (`*_unity.c`) that #includes the whole group's original,
// unmodified sources -- same compiled code, far fewer/shorter argv entries.
//
// CELT stays un-merged: celt_decoder.c/celt_encoder.c each `#define
// CELT_DECODER_C`/`CELT_ENCODER_C` before including celt.h so that one
// header (opus_custom.h) reveals a couple of internal-only prototypes to
// that file alone. In a shared unity TU, whichever file's includes reach
// that header *first* (not necessarily celt_decoder.c/celt_encoder.c
// themselves) permanently decides the header's include-guarded content for
// the rest of the file, hiding those prototypes from the very files that
// need them -- a real cross-file miscompile, not just a name clash.
//
// celt/mdct.c is vendored as celt_mdct.c and silk/PLC.c as silk_plc.c
// (content unchanged): both previously collided -- one case-insensitively
// -- with liblc3's own src/mdct.c / src/plc.c. cl.exe writes one object
// file per source basename with no way to namespace it per source tree, so
// without the rename the two would silently overwrite each other's .obj
// and leave liblc3's own symbols unresolved at link time.
const List<String> _celtSources = [
  'src/opus/celt/bands.c',
  'src/opus/celt/celt.c',
  'src/opus/celt/celt_decoder.c',
  'src/opus/celt/celt_encoder.c',
  'src/opus/celt/celt_lpc.c',
  'src/opus/celt/celt_mdct.c',
  'src/opus/celt/cwrs.c',
  'src/opus/celt/entcode.c',
  'src/opus/celt/entdec.c',
  'src/opus/celt/entenc.c',
  'src/opus/celt/kiss_fft.c',
  'src/opus/celt/laplace.c',
  'src/opus/celt/mathops.c',
  'src/opus/celt/modes.c',
  'src/opus/celt/pitch.c',
  'src/opus/celt/quant_bands.c',
  'src/opus/celt/rate.c',
  'src/opus/celt/vq.c',
];

const List<String> _opusSilkUnity = ['src/opus/silk/silk_unity.c'];
const List<String> _opusSilkFloatUnity = ['src/opus/silk/float/silk_float_unity.c'];
const List<String> _opusSrcUnity = ['src/opus/src/opus_unity.c'];

// libopusenc does NOT need libogg: it ships its own minimal ogg page writer
// (ogg_packer.c, the oggp_* functions below) precisely so that dependency
// can be dropped -- nothing here references ogg_stream_*/<ogg/ogg.h>.
//
// NOT unity-built: opusenc.c and ogg_packer.c each define their own static
// `shift_buffer` helper with a different signature -- merged into one
// translation unit that's a hard redefinition error (caught at compile
// time), not just a cosmetic name clash, so this one small group stays as
// separate files.
const List<String> _libopusencSources = [
  'src/libopusenc/src/ogg_packer.c',
  'src/libopusenc/src/opus_header.c',
  'src/libopusenc/src/opusenc.c',
  'src/libopusenc/src/picture.c',
  'src/libopusenc/src/resample.c',
  'src/libopusenc/src/unicode_support.c',
];

void main(List<String> args) async {
  await build(args, (config, output) async {
    final cbuilder = CBuilder.library(
      name: 'lc3_decoder',
      assetName: 'lc3_decoder.dart',
      sources: [
        ..._lc3Sources,
        ..._celtSources,
        ..._opusSilkUnity,
        ..._opusSilkFloatUnity,
        ..._opusSrcUnity,
        ..._libopusencSources,
        'src/shim.c',
      ],
      includes: [
        'src/liblc3/include',
        'src/liblc3/src',
        'src/opus/include',
        'src/opus/celt',
        'src/opus/silk',
        'src/opus/silk/float',
        'src/libopusenc/include',
      ],
      // Supplies OPUS_BUILD/USE_ALLOCA/OPE_BUILD/RANDOM_PREFIX/OUTSIDE_SPEEX/
      // PACKAGE_* to every source file, standing in for the config.h that
      // autotools/CMake would otherwise generate for these vendored libs.
      forcedIncludes: ['src/build_config.h'],
      // On Android/Linux libm is its own library and clang never links it
      // implicitly; opus' float path references exp/log/pow, and a `-shared`
      // link happily leaves them undefined until dlopen fails on-device.
      libraries: [if (config.config.code.targetOS == OS.android || config.config.code.targetOS == OS.linux) 'm'],
    );
    await cbuilder.run(input: config, output: output, logger: Logger('')..level = Level.ALL);
  });
}
