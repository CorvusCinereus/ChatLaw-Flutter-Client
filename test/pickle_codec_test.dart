// @file pickle_codec_test.dart
// @brief 分帧 pickle 解析测试
//
// 样例字节由真实 Python 生成（见 test/support/pickle_fixtures.dart），
// 确保解码器与服务端实际产出的格式一致。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatlaw/services/pickle_codec.dart';

import 'support/pickle_fixtures.dart';

void main() {
  group('decodePicklePayload', () {
    test('解析 Python pickle 出的字符串', () {
      expect(decodePicklePayload(pickleBytes('你好')), '你好');
      expect(decodePicklePayload(pickleBytes('<END>')), '<END>');
      expect(
        decodePicklePayload(pickleBytes('根据《中华人民共和国消防法》第五十一条')),
        '根据《中华人民共和国消防法》第五十一条',
      );
      expect(
        decodePicklePayload(pickleBytes('[ServerError] 生成失败')),
        '[ServerError] 生成失败',
      );
    });

    test('未知 opcode 抛出可读异常', () {
      // 0x99 不是本解码器支持的 opcode
      expect(
        () => decodePicklePayload(Uint8List.fromList([0x99])),
        throwsA(isA<PickleDecodeException>()),
      );
    });
  });

  group('InferFrameDecoder', () {
    test('单帧解析', () {
      final decoder = InferFrameDecoder();
      expect(decoder.addChunk(framedPickle('你好')), ['你好']);
      expect(decoder.hasPendingBytes, isFalse);
    });

    test('一次到达多帧', () {
      final decoder = InferFrameDecoder();
      final joined = <int>[
        ...framedPickle('你好'),
        ...framedPickle('，世界'),
        ...framedPickle('<END>'),
      ];
      expect(decoder.addChunk(joined), ['你好', '，世界', '<END>']);
    });

    test('帧被拆成多次到达（模拟 TCP 分包，含帧头跨界）', () {
      final decoder = InferFrameDecoder();
      final bytes = framedPickle('你好');
      final out = <String>[];

      for (final b in bytes) {
        out.addAll(decoder.addChunk([b]));
      }
      expect(out, ['你好']);
      expect(decoder.hasPendingBytes, isFalse);
    });

    test('半个帧滞留时标记未完成，补齐后可解析', () {
      final decoder = InferFrameDecoder();
      final bytes = framedPickle('你好');
      decoder.addChunk(bytes.sublist(0, bytes.length - 3));
      expect(decoder.hasPendingBytes, isTrue);
      expect(decoder.addChunk(bytes.sublist(bytes.length - 3)), ['你好']);
      expect(decoder.hasPendingBytes, isFalse);
    });

    test('帧长度非法时抛异常', () {
      final decoder = InferFrameDecoder();
      final bogus = Uint8List(8);
      ByteData.sublistView(bogus).setUint64(0, kMaxFrameLength + 1, Endian.big);
      expect(
        () => decoder.addChunk(bogus),
        throwsA(isA<PickleDecodeException>()),
      );
    });
  });
}
