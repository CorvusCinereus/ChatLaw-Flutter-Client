// @file inference_client_test.dart
// @brief 推理通信客户端测试：对本地 HttpServer 模拟服务端，验证协议细节
//
// 覆盖：健康检查、/infer 请求体与 Content-Length、流式分帧解码、心跳 PING、
// 错误帧处理、提前取消时发送 STOP。
// 端口用随机端口注入，不依赖服务端实际部署。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatlaw/services/inference_client.dart';

import 'support/pickle_fixtures.dart';

void main() {
  late HttpServer dataServer;
  late HttpServer heartbeatServer;
  late int dataPort;
  late int heartbeatPort;

  Future<void> Function(HttpRequest request)? onData;
  var pings = 0;
  var stops = 0;

  setUp(() async {
    dataServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    heartbeatServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dataPort = dataServer.port;
    heartbeatPort = heartbeatServer.port;
    onData = null;
    pings = 0;
    stops = 0;

    dataServer.listen((request) {
      final handler = onData;
      if (handler == null) {
        request.response.statusCode = 500;
        request.response.close();
        return;
      }
      unawaited(handler(request).catchError((Object _) {}));
    });

    heartbeatServer.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (payload['action'] == 'STOP') {
        stops += 1;
      } else {
        pings += 1;
      }
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'reply': 'PONG'}));
      await request.response.close();
    });
  });

  tearDown(() async {
    await dataServer.close(force: true);
    await heartbeatServer.close(force: true);
  });

  InferenceClient buildClient({Duration? heartbeatInterval}) => InferenceClient(
        host: '127.0.0.1',
        dataPort: dataPort,
        heartbeatPort: heartbeatPort,
        heartbeatInterval:
            heartbeatInterval ?? const Duration(milliseconds: 40),
      );

  test('健康检查：服务端 200 时返回 null', () async {
    onData = (request) async {
      expect(request.uri.path, kHealthPath);
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'service': 'data'}));
      await request.response.close();
    };

    expect(await buildClient().checkHealth(), isNull);
  });

  test('健康检查：端口不通时返回可读错误', () async {
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close(force: true);

    final client = InferenceClient(
      host: '127.0.0.1',
      dataPort: deadPort,
      heartbeatPort: heartbeatPort,
    );
    final error = await client.checkHealth();
    expect(error, isNotNull);
    expect(error, contains('无法连接'));
  });

  test('推理：请求体为 pickle 字节（含 Content-Length），响应按帧流式返回', () async {
    final receivedBody = <int>[];
    var receivedContentLength = -1;

    onData = (request) async {
      expect(request.uri.path, kInferPath);
      receivedContentLength = request.headers.contentLength;
      for (final chunk in await request.toList()) {
        receivedBody.addAll(chunk);
      }

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(framedPickle('你好'));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response
        ..add(framedPickle('，世界'))
        ..add(framedPickle('<END>'));
      await request.response.close();
    };

    final payload = <int>[10, 20, 30, 40, 50];
    final chunks = await buildClient().infer(payload).toList();

    expect(chunks, ['你好', '，世界']);
    expect(receivedBody, payload);
    // 服务端按 Content-Length 读 body：必须显式设置（默认 chunked 会读成空体）
    expect(receivedContentLength, payload.length);
    // 生成期间持续心跳
    expect(pings, greaterThan(0));
    // 正常结束不应发送 STOP
    expect(stops, 0);
  });

  test('推理：收到 [ServerError] 帧时抛 InferenceException', () async {
    onData = (request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(framedPickle('[ServerError] 生成失败'))
        ..add(framedPickle('<END>'));
      await request.response.close();
    };

    await expectLater(
      buildClient().infer(const [1, 2, 3]).toList(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('生成失败'),
        ),
      ),
    );
  });

  test('推理：HTTP 非 200 时抛异常并带上响应体', () async {
    onData = (request) async {
      request.response
        ..statusCode = 400
        ..write('missing request body');
      await request.response.close();
    };

    await expectLater(
      buildClient().infer(const [1]).toList(),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'message',
          contains('missing request body'),
        ),
      ),
    );
  });

  test('推理：提前取消订阅会向服务端发送 STOP', () async {
    onData = (request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(framedPickle('你好'));
      await request.response.flush();
      // 保持连接一段时间，模拟长时间的流式生成
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await request.response.close();
    };

    final first = await buildClient().infer(const [1]).first;
    expect(first, '你好');

    // 取消订阅后应发出一次 STOP
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(stops, greaterThan(0));
  });
}
