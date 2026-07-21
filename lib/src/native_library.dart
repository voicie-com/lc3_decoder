import 'dart:ffi' as ffi;
import 'dart:io';

import '../lc3_decoder_bindings_generated.dart';

const String _libName = 'lc3_decoder';

/// Where the native asset can be found, most specific first.
///
/// Apple targets need all three. A packaged app wraps the dylib in a framework
/// for code signing; a bare `lib<name>.dylib` covers it having landed on the
/// dynamic loader's search path; and `flutter test` on macOS leaves it under
/// `build/`, which needs an explicit relative path because dlopen -- unlike
/// Windows' LoadLibrary -- does not search the working directory for a plain
/// filename.
List<String> _candidateNames() {
  if (Platform.isMacOS || Platform.isIOS) {
    return [
      '$_libName.framework/$_libName',
      'lib$_libName.dylib',
      if (Platform.isMacOS) 'build/native_assets/macos/lib$_libName.dylib',
    ];
  }
  if (Platform.isAndroid || Platform.isLinux) return ['lib$_libName.so'];
  if (Platform.isWindows) return ['$_libName.dll'];
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}

/// The single native asset backing this package: liblc3 (decode) and
/// libopus/libopusenc (encode + mux) are compiled into one library by
/// `hook/build.dart`, so there is only ever one dynamic library to load.
final ffi.DynamicLibrary nativeLibrary = () {
  final failures = <String>[];
  for (final name in _candidateNames()) {
    try {
      return ffi.DynamicLibrary.open(name);
    } on ArgumentError catch (e) {
      failures.add('  $name -> ${e.message}');
    }
  }
  throw StateError('Could not load the $_libName native asset. Tried:\n${failures.join('\n')}');
}();

/// Bindings to every native function in [nativeLibrary] (LC3 decode + Opus
/// encode/mux), shared by all Dart wrappers in this package.
final Lc3DecoderBindings nativeBindings = Lc3DecoderBindings(nativeLibrary);
