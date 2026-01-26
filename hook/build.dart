import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final cbuilder = CBuilder.library(
      name: 'lc3_decoder',
      assetName: 'lc3_decoder.dart',
      sources: [
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
      ],
      includes: ['src/liblc3/include', 'src/liblc3/src'],
    );
    await cbuilder.run(
      input: config,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
