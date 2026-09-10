// @file chat_pipeline.dart
// @brief 客户端流水线服务：以外部 Python 子进程驱动 rag → build → tokenize
//
// 与 python/ 模块的文件链约定对应（见 docs/client_modules.md）：
//   1. runRag:    python -m python.rag   （env: APPDATA_DIR + RAG_QUERY）
//                 → 产出 {APPDATA_DIR}/pipeline/rag_result.json
//   2. runBuild:  python -m python.build （读 rag_result.json → prompt.txt）
//   3. runTokenize: python -m python.tokenize（读 prompt.txt → model_inputs.pkl）
//
// 开发期为外部 Python 子进程实现（配置见 lib/internal/python_env.dart）；
// 后续接入 serious_python（Android 内嵌）时改写本服务的调用实现即可，
// ChatPage 只依赖本服务的三个方法，UI 不受影响。

import 'dart:convert';
import 'dart:io';

import 'package:chatlaw/internal/python_env.dart';

/// 内嵌 Python 服务的本地端口（与仓库根 main.py 的 DEFAULT_PORT 保持一致）
const int kPythonServicePort = 18765;

/// 单条检索结果（对应 rag_result.json results[] 的归一化记录）
class RagDoc {
  final String lawName;
  final String article;
  final String content;
  final String source;

  RagDoc({
    required this.lawName,
    required this.article,
    required this.content,
    required this.source,
  });

  factory RagDoc.fromJson(Map<String, dynamic> json) => RagDoc(
        lawName: json['law_name'] as String? ?? '',
        article: json['article'] as String? ?? '',
        content: json['content'] as String? ?? '',
        source: json['source'] as String? ?? '',
      );

  /// 面板标题：《法律名》条号
  String get title => '《$lawName》$article';
}

/// 流水线阶段执行异常
class PipelineException implements Exception {
  final String message;

  PipelineException(this.message);

  @override
  String toString() => message;
}

/// 客户端流水线服务
class ChatPipeline {
  /// 测试注入缝：widget 测试中可替换为假实现（见 test/chat_page_flow_test.dart）
  static ChatPipeline? debugOverride;

  final String pythonExe;
  final String appDataDir;
  final String repoRoot;

  ChatPipeline({
    String? pythonExe,
    String? appDataDir,
    String? repoRoot,
  })  : pythonExe = pythonExe ?? kPythonExe,
        appDataDir = appDataDir ?? kAppDataDir,
        repoRoot = repoRoot ?? pythonRepoRoot;

  /// 环境变量：注入 APPDATA_DIR（资源根）与可选 RAG_QUERY
  Map<String, String> _env({String? ragQuery}) => {
        ...Platform.environment,
        'APPDATA_DIR': appDataDir,
        'PYTHONIOENCODING': 'utf-8',
        if (ragQuery != null && ragQuery.isNotEmpty) 'RAG_QUERY': ragQuery,
      };

  Future<void> _runModule(String module, {String? ragQuery}) async {
    if (!File(pythonExe).existsSync()) {
      throw PipelineException(
        'Python 解释器不存在: $pythonExe\n'
        '请在 lib/internal/python_env.dart 中配置正确的解释器路径，'
        '并确保已安装 python/requirements.txt 依赖。',
      );
    }

    final result = await Process.run(
      pythonExe,
      ['-m', module],
      workingDirectory: repoRoot,
      environment: _env(ragQuery: ragQuery),
    );

    if (result.exitCode != 0) {
      final stderrTail = (result.stderr as String? ?? '')
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(8)
          .join('\n');
      throw PipelineException('[$module] 执行失败（退出码 ${result.exitCode}）'
          '${stderrTail.isEmpty ? '' : ':\n$stderrTail'}');
    }
  }

  /// 步骤 1：真实 RAG 检索，返回检索到的法条列表
  ///
  /// Android：HTTP 调用内嵌 Python 服务 /rag；桌面：外部 Python 子进程。
  Future<List<RagDoc>> runRag(String question) async {
    if (Platform.isAndroid) {
      final body = await _httpPost('/rag', {'question': question});
      final results = (body['docs'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RagDoc.fromJson)
          .toList();
      return results;
    }

    await _runModule('python.rag', ragQuery: question);

    final resultFile = File('$appDataDir/pipeline/rag_result.json');
    if (!resultFile.existsSync()) {
      throw PipelineException('RAG 执行完成但未找到结果文件: ${resultFile.path}');
    }
    final data = jsonDecode(resultFile.readAsStringSync()) as Map<String, dynamic>;
    final results = (data['results'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(RagDoc.fromJson)
        .toList();
    return results;
  }

  /// 步骤 2：真实构建 prompt（读 rag_result.json → prompt.txt）
  Future<void> runBuild() async {
    if (Platform.isAndroid) {
      await _httpPost('/build', const {});
      return;
    }
    await _runModule('python.build');
  }

  /// 步骤 3：真实分词（读 prompt.txt → model_inputs.pkl）
  Future<void> runTokenize() async {
    if (Platform.isAndroid) {
      await _httpPost('/tokenize', const {});
      return;
    }
    await _runModule('python.tokenize');
  }

  /// Android：调用内嵌 Python HTTP 服务（main.py，serious_python 内嵌）
  ///
  /// 首次启动需解包 app.zip（数百 MB）并加载依赖，python 服务可能数分钟才就绪，
  /// 故对连接做长时间重试（约 3 分钟）；期间 UI 不报错、耐心等待。
  Future<Map<String, dynamic>> _httpPost(
    String path,
    Map<String, dynamic> payload,
  ) async {
    const maxAttempts = 120;
    const retryDelay = Duration(milliseconds: 1500);
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse('http://127.0.0.1:$kPythonServicePort$path'))
            .timeout(const Duration(seconds: 10));
        request.headers.contentType = ContentType.json;
        // Android 内嵌 Python 服务端只读 Content-Length（chunked 编码会导致
        // 服务端读到 0 字节、body 为空）。显式设置字节长度以保证 body 完整送达。
        final bodyBytes = utf8.encode(jsonEncode(payload));
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
        final response = await request.close().timeout(const Duration(seconds: 300));
        final text = await response.transform(utf8.decoder).join();
        final body = jsonDecode(text) as Map<String, dynamic>;
        if (body['ok'] == true) {
          return body;
        }
        throw PipelineException('Python 服务执行失败: ${body['error'] ?? '未知错误'}');
      } on SocketException catch (e) {
        // 服务尚未就绪（内嵌 Python 启动/解包中）→ 稍后重试
        lastError = e;
        await Future<void>.delayed(retryDelay);
      } finally {
        client.close(force: true);
      }
    }
    throw PipelineException(
        '无法连接内嵌 Python 服务（127.0.0.1:$kPythonServicePort，等待约 ${maxAttempts * retryDelay.inMilliseconds ~/ 1000}s 后仍失败）：$lastError\n'
        '请确认首次启动的解包已完成，或查看 adb logcat 中 [chatlaw] SeriousPython 日志与 '
        '{数据目录}/flet/app/resources/pipeline/python_error.log');
  }

  /// 检查内嵌 Python 服务是否已经就绪。
  Future<bool> isPythonServiceReady() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$kPythonServicePort/health'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      final text = await response.transform(utf8.decoder).join();
      final body = jsonDecode(text) as Map<String, dynamic>;
      return body['ok'] == true;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
