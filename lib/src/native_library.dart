import 'dart:ffi' as ffi;
import 'dart:io';

import '../lc3_decoder_bindings_generated.dart';

const String _libName = 'lc3_decoder';

/// The single native asset backing this package: liblc3 (decode) and
/// libopus/libogg/libopusenc (encode + mux) are compiled into one library
/// by `hook/build.dart`, so there is only ever one dynamic library to load.
final ffi.DynamicLibrary nativeLibrary = () {
  if (Platform.isMacOS || Platform.isIOS) {
    // On iOS, native assets bundle the library as a framework in the app's Frameworks folder.
    // We need to load it explicitly by its framework path.
    return ffi.DynamicLibrary.open('lc3_decoder.framework/lc3_decoder');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// Bindings to every native function in [nativeLibrary] (LC3 decode + Opus
/// encode/mux), shared by all Dart wrappers in this package.
final Lc3DecoderBindings nativeBindings = Lc3DecoderBindings(nativeLibrary);
