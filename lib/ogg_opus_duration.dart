import 'dart:io';
import 'dart:typed_data';

const List<int> _oggCapturePattern = [0x4F, 0x67, 0x67, 0x53]; // "OggS"
const List<int> _opusHeadMagic = [
  0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
];

const int _oggPageHeaderFixedBytes = 27;
const int _eosFlag = 0x04;
const int _bosFlag = 0x02;
const int _opusGranuleRateHz = 48000; // Ogg Opus granule positions are always 48 kHz.

// Bounded read windows: enough to comfortably hold the tiny BOS/ID-header
// page and the largest possible single Ogg page (27B header + 255B segment
// table + 255*255B payload) at the tail, without ever reading a whole
// multi-megabyte recording into memory.
const int _headWindowBytes = 8 * 1024;
const int _tailWindowBytes = 128 * 1024;

/// Reads the exact duration (in milliseconds) of an Ogg Opus file by
/// locating its granule position, without decoding any audio.
///
/// Fail-safe by contract: returns `null` for anything that isn't a clean,
/// single-stream Ogg Opus file (malformed pages, a missing or wrong-serial
/// end-of-stream page, a chained/multi-stream file, a truncated segment
/// table, or a granule position smaller than the pre-skip) instead of
/// throwing -- callers use this as a best-effort upgrade over a bitrate
/// estimate and must never have an upload aborted by it.
///
/// Reads only two bounded blocks (file head and tail), never the whole
/// file, so memory use stays constant regardless of file size.
Future<int?> readOggOpusDurationMs(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final length = await raf.length();
    if (length < _oggPageHeaderFixedBytes) return null;

    final headSize = length < _headWindowBytes ? length : _headWindowBytes;
    await raf.setPosition(0);
    final head = await raf.read(headSize);

    final bos = _parsePageAt(head, 0);
    if (bos == null) return null;
    if (!bos.isFirstPage || (bos.headerType & _bosFlag) == 0) return null;
    if (!_matchesAt(head, bos.payloadStart, _opusHeadMagic)) return null;
    // "OpusHead"(8B) + version(1B) + channel_count(1B) + pre_skip(2B) + ...
    if (bos.payloadStart + 12 > head.length) return null;
    final preSkip = ByteData.sublistView(head).getUint16(bos.payloadStart + 10, Endian.little);

    final tailSize = length < _tailWindowBytes ? length : _tailWindowBytes;
    final tailStart = length - tailSize;
    await raf.setPosition(tailStart);
    final tail = await raf.read(tailSize);

    final lastOggSIndex = _lastIndexOfPattern(tail, _oggCapturePattern);
    if (lastOggSIndex < 0) return null;

    final eos = _parsePageAt(tail, lastOggSIndex);
    if (eos == null) return null;
    if ((eos.headerType & _eosFlag) == 0) return null;
    if (eos.serialNumber != bos.serialNumber) return null;
    if (eos.granulePosition < preSkip) return null;

    final samples = eos.granulePosition - preSkip;
    return (samples * 1000) ~/ _opusGranuleRateHz;
  } catch (_) {
    return null;
  } finally {
    try {
      await raf?.close();
    } catch (_) {
      // Best-effort close; the read already succeeded or failed on its own.
    }
  }
}

class _OggPage {
  final bool isFirstPage;
  final int headerType;
  final int granulePosition;
  final int serialNumber;
  final int payloadStart;

  const _OggPage({
    required this.isFirstPage,
    required this.headerType,
    required this.granulePosition,
    required this.serialNumber,
    required this.payloadStart,
  });
}

/// Parses one Ogg page starting at [start] within [bytes]. Returns `null` if
/// the capture pattern, version, or segment table don't fit within [bytes]
/// -- including a segment table truncated by the end of the file.
_OggPage? _parsePageAt(Uint8List bytes, int start) {
  if (start < 0 || start + _oggPageHeaderFixedBytes > bytes.length) return null;
  if (!_matchesAt(bytes, start, _oggCapturePattern)) return null;

  final bd = ByteData.sublistView(bytes);
  final version = bytes[start + 4];
  if (version != 0) return null;
  final headerType = bytes[start + 5];
  final granulePosition = bd.getInt64(start + 6, Endian.little);
  final serialNumber = bd.getUint32(start + 14, Endian.little);
  final pageSequence = bd.getUint32(start + 18, Endian.little);
  final pageSegments = bytes[start + 26];

  final segmentTableStart = start + _oggPageHeaderFixedBytes;
  if (segmentTableStart + pageSegments > bytes.length) return null; // truncated segment table

  var payloadLength = 0;
  for (var i = 0; i < pageSegments; i++) {
    payloadLength += bytes[segmentTableStart + i];
  }
  final payloadStart = segmentTableStart + pageSegments;
  if (payloadStart + payloadLength > bytes.length) return null;

  return _OggPage(
    isFirstPage: pageSequence == 0,
    headerType: headerType,
    granulePosition: granulePosition,
    serialNumber: serialNumber,
    payloadStart: payloadStart,
  );
}

bool _matchesAt(Uint8List bytes, int start, List<int> pattern) {
  if (start < 0 || start + pattern.length > bytes.length) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (bytes[start + i] != pattern[i]) return false;
  }
  return true;
}

int _lastIndexOfPattern(Uint8List bytes, List<int> pattern) {
  for (var i = bytes.length - pattern.length; i >= 0; i--) {
    if (_matchesAt(bytes, i, pattern)) return i;
  }
  return -1;
}
