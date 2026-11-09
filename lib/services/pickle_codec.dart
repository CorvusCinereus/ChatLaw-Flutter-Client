/**
 * @file pickle_codec.dart
 * @brief 解析 ChatLaw 服务端 /infer 的分帧 pickle 响应
 *
 * 协议（见 chatlaw/network/http_transport.py: send_pickled_frame）：
 *   响应体是连续分帧，每帧 = 8 字节**大端**长度 + 该长度的 pickle 数据；
 *   pickle 内容是服务端 `pickle.dumps(chunk)` 的结果，chunk 为文本增量（str），
 *   结束帧的内容是 "<END>"，服务端异常时会先发一个 "[ServerError] ..." 文本帧。
 *
 * 这里只实现**解码**：请求方向的 pickle 由设备端内嵌 Python 生成（numpy 数组
 * 只有 Python 侧才能产出），Dart 只需原样转发字节，无需编码 pickle。
 *
 * 服务端 `pickle.dumps(str)` 在 Python 3.x 下产出协议 5 的字节流，形如：
 *   80 05 | 95 <8 字节小端长度> | 8c <1 字节长度> <utf8> | 94 | 2e
 * 本解码器只处理字符串/字节串及若干前缀 opcode，足够覆盖该协议。
 */

import 'dart:convert';
import 'dart:typed_data';

/// 服务端流结束标记
const String kEndMarker = '<END>';

/// 服务端错误帧前缀（出现时应作为错误提示，而非回答内容）
const String kServerErrorPrefix = '[ServerError]';

/// 单个外层帧的最大长度（防御性上限：16MB）
const int kMaxFrameLength = 16 * 1024 * 1024;

/// pickle 内容无法解析
class PickleDecodeException implements Exception {
  final String message;
  PickleDecodeException(this.message);

  @override
  String toString() => message;
}

/// 解码一个**完整**帧内的 pickle 数据，返回其中的字符串（或字节串）。
///
/// 服务端只 pickles 一个 str（或 bytes），因此按顺序扫描 opcode、取最后一个
/// 字符串/字节串值即可；遇到 STOP 结束。
Object? decodePicklePayload(Uint8List bytes) {
  var i = 0;
  Object? result;

  while (i < bytes.length) {
    final op = bytes[i];
    i += 1;

    switch (op) {
      case 0x80: // PROTO：后跟 1 字节协议号
        i += 1;
        break;

      case 0x95: // FRAME：后跟 8 字节小端长度（pickle 内部分帧，跳过）
        i += 8;
        break;

      case 0x8c: // SHORT_BINUNICODE：1 字节长度 + utf8
      case 0x55: // SHORT_BINUNICODE（协议 3 的别名）
        result = utf8.decode(_slice(bytes, i + 1, bytes[i]));
        i += 1 + bytes[i];
        break;

      case 0x58: // BINUNICODE：4 字节小端长度 + utf8
        final n = _readLe(bytes, i, 4);
        result = utf8.decode(_slice(bytes, i + 4, n));
        i += 4 + n;
        break;

      case 0x8d: // BINUNICODE8：8 字节小端长度 + utf8
        final n = _readLe(bytes, i, 8);
        result = utf8.decode(_slice(bytes, i + 8, n));
        i += 8 + n;
        break;

      case 0x43: // SHORT_BINBYTES：1 字节长度
        result = _slice(bytes, i + 1, bytes[i]);
        i += 1 + bytes[i];
        break;

      case 0x42: // BINBYTES：4 字节小端长度
        final n = _readLe(bytes, i, 4);
        result = _slice(bytes, i + 4, n);
        i += 4 + n;
        break;

      case 0x8e: // BINBYTES8：8 字节小端长度
        final n = _readLe(bytes, i, 8);
        result = _slice(bytes, i + 8, n);
        i += 8 + n;
        break;

      case 0x94: // MEMOIZE
      case 0x71: // BINPUT
      case 0x72: // LONG_BINPUT
        break;

      case 0x2e: // STOP
        return result;

      case 0x4e: // NONE
        result = null;
        break;

      default:
        throw PickleDecodeException(
          '不支持的 pickle opcode: 0x${op.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }

  return result;
}

Uint8List _slice(Uint8List bytes, int start, int length) {
  if (length < 0 || start + length > bytes.length) {
    throw PickleDecodeException('pickle 数据长度越界（start=$start, len=$length）');
  }
  return Uint8List.sublistView(bytes, start, start + length);
}

int _readLe(Uint8List bytes, int start, int width) {
  if (start + width > bytes.length) {
    throw PickleDecodeException('pickle 长度字段越界');
  }
  var value = 0;
  for (var k = width - 1; k >= 0; k--) {
    value = (value << 8) | bytes[start + k];
  }
  return value;
}

/// 增量解析器：把网络字节流切成外层帧，逐帧产出解码后的文本。
class InferFrameDecoder {
  final List<int> _buffer = <int>[];

  /// 追加一段字节，返回本次新解析出的文本块列表（可能为空）。
  List<String> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);

    final texts = <String>[];
    while (true) {
      if (_buffer.length < 8) break;

      // 外层帧头为 8 字节**大端**长度（http_transport.send_pickled_frame）
      var frameLength = 0;
      for (var k = 0; k < 8; k++) {
        frameLength = (frameLength << 8) | _buffer[k];
      }
      if (frameLength < 0 || frameLength > kMaxFrameLength) {
        throw PickleDecodeException('帧长度异常: $frameLength');
      }
      if (_buffer.length < 8 + frameLength) break;

      final payload = Uint8List.fromList(
        _buffer.sublist(8, 8 + frameLength),
      );
      _buffer.removeRange(0, 8 + frameLength);

      final decoded = decodePicklePayload(payload);
      if (decoded == null) continue;
      if (decoded is String) {
        texts.add(decoded);
      } else if (decoded is List<int>) {
        texts.add(utf8.decode(decoded, allowMalformed: true));
      } else {
        texts.add(decoded.toString());
      }
    }
    return texts;
  }

  /// 是否还有残留的半个帧（用于提示连接被提前关闭）
  bool get hasPendingBytes => _buffer.isNotEmpty;
}
