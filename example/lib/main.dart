import 'dart:io';
import 'package:flutter/services.dart'; // Add services for rootBundle
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lc3_decoder/lc3_decoder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Constants from C code (matching simple_decoder.dart)
// ignore: constant_identifier_names
const int LC3_FILE_ID = 0xCC1C; // (0x1C | (0xCC << 8))

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LC3 Decoder GUI',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? _selectedFilePath;
  String? _outputFilePath;
  String _statusLog = '';
  bool _isDecoding = false;
  final ScrollController _scrollController = ScrollController();

  void _log(String message) {
    setState(() {
      _statusLog += '$message\n';
    });
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFile() async {
    _log('Picking file...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lc3', 'bin'],
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          setState(() {
            _selectedFilePath = path;
            _outputFilePath = null; // Reset output
          });
          _log('Selected: $path');
        }
      } else {
        _log('File selection canceled.');
      }
    } catch (e) {
      _log('Error picking file: $e');
    }
  }

  Future<void> _loadAssetFile() async {
    _log('Loading asset file...');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}test.lc3');

      // Always overwrite for testing
      final data = await rootBundle.load('assets/test.lc3');
      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes, flush: true);

      setState(() {
        _selectedFilePath = file.path;
        _outputFilePath = null;
      });
      _log('Loaded asset to: ${file.path}');
    } catch (e) {
      _log('Error loading asset file: $e');
    }
  }

  Future<void> _decodeFile() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isDecoding = true;
      _statusLog = ''; // Clear log on new run
      _outputFilePath = null;
    });
    _log('Starting decoding...');

    try {
      final inputFile = File(_selectedFilePath!);
      // Note: On Android with file_picker, accessible paths might be limited or cached.
      // Copying to invalid path can fail.

      final bytes = await inputFile.readAsBytes();
      final ByteData bd = bytes.buffer.asByteData();
      int offset = 0;

      // --- Parse Header (18 bytes) ---
      if (bytes.length < 18) {
        throw Exception('File too short to contain header');
      }

      final fileId = bd.getUint16(offset, Endian.little);
      offset += 2;
      if (fileId != LC3_FILE_ID) {
        _log(
          'Warning: File ID 0x${fileId.toRadixString(16).toUpperCase()} does not match expected 0x${LC3_FILE_ID.toRadixString(16).toUpperCase()}',
        );
      }

      // final headerSize = bd.getUint16(offset, Endian.little);
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

      _log('--- Header Info ---');
      _log('Sample Rate: $sampleRate Hz');
      _log('Bitrate: $bitrate bps');
      _log('Duration: $frameDurationUs us');
      _log('Channels: $channels');

      if (channels != 1) {
        _log('Warning: This decoder assumes 1 channel.');
      }

      // --- Initialize Decoder ---
      Lc3Decoder? decoder;
      try {
        decoder = Lc3Decoder(frameDurationUs, sampleRate);
      } catch (e) {
        _log('Failed to initialize decoder: $e');
        return;
      }

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
          _log('Error: Incomplete frame at byte $offset.');
          break;
        }

        final frameData = bytes.sublist(offset, offset + frameSize);
        offset += frameSize;

        try {
          // Note: decode() can take Uint8List directly
          final pcm = decoder.decode(frameData);
          outputBuffer.add(pcm);
          frameCount++;
        } catch (e) {
          _log('Decode error at frame $frameCount: $e');
          break;
        }

        // Yield to UI thread occasionally to keep UI responsive
        if (frameCount % 100 == 0) await Future.delayed(Duration.zero);
      }

      decoder.dispose();
      stopwatch.stop();

      // --- Save Output ---
      // Get temporary directory for saving output
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          '${_selectedFilePath!.split(RegExp(r'[/\\]')).last.replaceAll('.lc3', '')}.pcm';
      final outputFile = File(
        '${directory.path}${Platform.pathSeparator}$fileName',
      );

      _log('Writing output file...');
      await outputFile.writeAsBytes(outputBuffer.toBytes());

      setState(() {
        _outputFilePath = outputFile.path;
      });

      _log('Success!');
      _log(
        'Processed $frameCount frames in ${stopwatch.elapsedMilliseconds}ms.',
      );
      _log('Saved to internal storage: ${outputFile.path}');
      _log('Click "Share/Export" to save to device.');
    } catch (e) {
      _log('Fatal Error: $e');
    } finally {
      setState(() {
        _isDecoding = false;
      });
    }
  }

  Future<void> _shareFile() async {
    if (_outputFilePath == null) return;
    try {
      final file = XFile(_outputFilePath!);
      await SharePlus.instance.share(
        ShareParams(files: [file], text: 'Decoded LC3 PCM Audio'),
      );
    } catch (e) {
      _log('Error sharing file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LC3 Decoder GUI')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isDecoding ? null : _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Pick LC3 File'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _isDecoding ? null : _loadAssetFile,
              icon: const Icon(Icons.file_present),
              label: const Text('Load Asset (test.lc3)'),
            ),
            const SizedBox(height: 10),
            Text(
              _selectedFilePath == null
                  ? 'No file selected'
                  : 'Selected: ${_selectedFilePath!.split(Platform.pathSeparator).last}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (_isDecoding) const LinearProgressIndicator(),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: (_selectedFilePath == null || _isDecoding)
                  ? null
                  : _decodeFile,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Decode to PCM'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _outputFilePath == null ? null : _shareFile,
              icon: const Icon(Icons.share),
              label: const Text('Share / Save Export'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Status Log:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _statusLog,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
