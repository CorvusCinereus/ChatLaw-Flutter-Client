// @file pickle_fixtures.dart
// @brief 测试用 pickle 样例（字节由真实 Python 生成，非手写）
//
// 生成方式：
//   python -c "import pickle;print(pickle.dumps('你好').hex())"
//
// 目的：确保 Dart 解码器与 Python `pickle.dumps` / 服务端 `send_pickled_frame`
// 的实际字节格式严格一致。

import 'dart:typed_data';

/// 文本 -> Python `pickle.dumps(text)` 的十六进制
const Map<String, String> pickleHex = {
  '你好': '8005950a000000000000008c06e4bda0e5a5bd942e',
  '，世界': '8005950d000000000000008c09efbc8ce4b896e7958c942e',
  '根据《中华人民共和国消防法》第五十一条':
      '8005953d000000000000008c39e6a0b9e68daee3808ae4b8ade58d8ee4babae6b091e585b1e5928ce59bbde6b688e998b2e6b395e3808be7acace4ba94e58d81e4b880e69da1942e',
  '<END>': '80059509000000000000008c053c454e443e942e',
  '[ServerError] 生成失败':
      '8005951e000000000000008c1a5b5365727665724572726f725d20e7949fe68890e5a4b1e8b4a5942e',
};

/// 十六进制字符串转字节
Uint8List hexToBytes(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 取某个文本的 pickle 字节
Uint8List pickleBytes(String text) {
  final hex = pickleHex[text];
  if (hex == null) {
    throw ArgumentError('未准备该文本的 pickle 样例: $text');
  }
  return hexToBytes(hex);
}

/// 加上服务端传输层帧头（8 字节**大端**长度）后的完整帧字节
Uint8List framedPickle(String text) {
  final payload = pickleBytes(text);
  final out = Uint8List(8 + payload.length);
  ByteData.sublistView(out).setUint64(0, payload.length, Endian.big);
  out.setRange(8, out.length, payload);
  return out;
}
