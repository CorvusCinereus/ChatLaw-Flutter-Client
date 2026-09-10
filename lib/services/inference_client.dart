/**
 * @file inference_client.dart
 * @brief 与 ChatLaw 推理服务器通信：健康检查 / 心跳 / /infer 流式推理
 *
 * 对照服务端实现（chatlaw/server/server_pt.py + chatlaw/network/http_transport.py）：
 *  - 心跳端口 6005：`POST /health`、`POST /heartbeat`（JSON）
 *  - 数据端口 6006：`POST /health`（JSON）、`POST /infer`（pickle 请求 + 分帧流式响应）
 *  - `/infer` 请求体 = pickle 序列化的模型输入；响应为「8 字节大端长度 + pickle」分帧，
 *    结束帧内容为 `<END>`；服务端异常时先发一个 `[ServerError] ...` 文本帧
 *  - 生成期间客户端须持续发送心跳（服务端 3 秒收不到 PING 会中止生成）
 *
 * 端口按服务端 config.yaml 固定，客户端只需要一个服务器 IP。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pickle_codec.dart';

/// 心跳端口（对应服务端 config.HEARTBEAT_PORT）
const int kHeartbeatPort = 6005;

/// 数据端口（对应服务端 config.DATA_PORT）
const int kDataPort = 6006;

const String kHealthPath = '/health';
const String kHeartbeatPath = '/heartbeat';
const String kInferPath = '/infer';

/// 心跳间隔 / 连接与响应超时
const Duration kHeartbeatInterval = Duration(seconds: 1);
const Duration kHeartbeatTimeout = Duration(seconds: 3);
const Duration kConnectTimeout = Duration(seconds: 5);

/// 推理通信异常
class InferenceException implements Exception {
  final String message;
  InferenceException(this.message);

  @override
  String toString() => message;
}

/// 推理服务器客户端
class InferenceClient {
  /// 测试注入缝：widget 测试中可替换为假实现
  static InferenceClient? debugOverride;

  /// 服务器 IP / 主机名
  final String host;

  /// 数据端口（默认 6006，与服务端 config.DATA_PORT 一致；仅测试需覆盖）
  final int dataPort;

  /// 心跳端口（默认 6005，与服务端 config.HEARTBEAT_PORT 一致；仅测试需覆盖）
  final int heartbeatPort;

  /// 心跳间隔（测试可缩短）
  final Duration heartbeatInterval;

  InferenceClient({
    required this.host,
    this.dataPort = kDataPort,
    this.heartbeatPort = kHeartbeatPort,
    this.heartbeatInterval = kHeartbeatInterval,
  });

  /// 健康检查数据端口是否可用。
  ///
  /// Returns:
  ///   null 表示正常；否则返回面向用户的错误描述（不抛异常）。
  Future<String?> checkHealth() async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('http://$host:$dataPort$kHealthPath'))
          .timeout(kConnectTimeout);
      request.headers.contentType = ContentType.json;
      final body = utf8.encode(jsonEncode({'probe': 'health'}));
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(kHeartbeatTimeout);
      final text = await utf8.decodeStream(response);
      if (response.statusCode != 200) {
        return '服务端 /health 返回 HTTP ${response.statusCode}：$text';
      }
      return null;
    } on SocketException catch (e) {
      return '无法连接服务器 $host:$dataPort（${e.osError?.message ?? e.message}）';
    } on TimeoutException {
      return '连接服务器 $host:$dataPort 超时';
    } catch (e) {
      return '健康检查失败：$e';
    } finally {
      client.close(force: true);
    }
  }

  /// 发起推理并逐块产出模型输出文本。
  ///
  /// [pickledInputs] 为模型输入的 pickle 字节（由设备端内嵌 Python 生成，
  /// 形如 `{"input_ids": ndarray, "attention_mask": ndarray}`）。
  ///
  /// 生成期间会自动维持心跳；流被提前取消时会向服务端发送一次 STOP。
  Stream<String> infer(List<int> pickledInputs) async* {
    final client = HttpClient();
    Timer? heartbeat;
    var finished = false;

    try {
      // 先启动心跳，避免服务端在长生成期间因心跳超时而中止
      heartbeat = Timer.periodic(heartbeatInterval, (_) => unawaited(_ping()));
      unawaited(_ping());

      final request = await client
          .postUrl(Uri.parse('http://$host:$dataPort$kInferPath'))
          .timeout(kConnectTimeout);
      request.headers.contentType = ContentType.binary;
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      // 服务端按 Content-Length 读取请求体，必须显式设置（默认 chunked 会读成空体）
      request.contentLength = pickledInputs.length;
      request.add(pickledInputs);

      final response = await request.close();
      if (response.statusCode != 200) {
        final text = await utf8.decodeStream(response);
        throw InferenceException(
          '服务端 $kInferPath 返回 HTTP ${response.statusCode}：$text',
        );
      }

      final decoder = InferFrameDecoder();
      var sawEnd = false;

      await for (final chunk in response) {
        for (final text in decoder.addChunk(chunk)) {
          if (text.trim() == kEndMarker) {
            sawEnd = true;
            break;
          }
          if (text.startsWith(kServerErrorPrefix)) {
            throw InferenceException('服务端推理失败：$text');
          }
          if (text.isEmpty) continue;
          yield text;
        }
        if (sawEnd) break;
      }

      if (!sawEnd) {
        throw InferenceException('连接被提前关闭，模型输出可能不完整');
      }
      finished = true;
    } on InferenceException {
      rethrow;
    } on SocketException catch (e) {
      throw InferenceException(
        '无法连接推理服务器 $host:$dataPort（${e.osError?.message ?? e.message}）',
      );
    } catch (e) {
      throw InferenceException('推理通信失败：$e');
    } finally {
      heartbeat?.cancel();
      // 提前中断（用户离开页面 / 取消订阅）时通知服务端停止生成
      if (!finished) unawaited(_ping(stop: true));
      client.close(force: true);
    }
  }

  /// 发送一次心跳；失败不中断推理（服务端会自行按超时中止）。
  Future<void> _ping({bool stop = false}) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('http://$host:$heartbeatPort$kHeartbeatPath'))
          .timeout(kHeartbeatTimeout);
      request.headers.contentType = ContentType.json;
      final body = utf8.encode(jsonEncode({'action': stop ? 'STOP' : 'PING'}));
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(kHeartbeatTimeout);
      await response.drain<void>();
    } catch (_) {
      // 忽略：心跳失败不应打断数据通道
    } finally {
      client.close(force: true);
    }
  }
}
