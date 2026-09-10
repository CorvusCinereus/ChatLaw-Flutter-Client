// @file chat_pipeline_real_test.dart
// @brief 真实流水线集成测试：外部 Python 子进程 + 真实资源（Windows 开发机）
//
// 依赖：lib/internal/python_env.dart 中的 kPythonExe（ChatLaw_env）与
//       kAppDataDir（D:\dev\chatlaw_android_resources，真实向量库/模型）。
// 运行：flutter test test/chat_pipeline_real_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatlaw/services/chat_pipeline.dart';

void main() {
  final pipeline = ChatPipeline();

  test('真实 RAG 检索返回相关法律条文', () async {
    final docs =
        await pipeline.runRag('因过失导致宿舍楼失火应承担什么责任？');

    expect(docs, isNotEmpty, reason: 'RAG 应命中法律条文');
    expect(docs.first.lawName, isNotEmpty);
    expect(docs.first.content, isNotEmpty);

    // ignore: avoid_print
    print('RAG 命中 ${docs.length} 条，前 3 条：');
    for (final d in docs.take(3)) {
      // ignore: avoid_print
      print('  - ${d.title}（source=${d.source}）');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('真实构建 prompt 与分词（文件链产物齐全）', () async {
    await pipeline.runBuild();
    await pipeline.runTokenize();

    final pipelineDir = '${pipeline.appDataDir}/pipeline';
    expect(File('$pipelineDir/prompt.txt').existsSync(), isTrue,
        reason: 'build 应产出 prompt.txt');
    expect(File('$pipelineDir/model_inputs.pkl').existsSync(), isTrue,
        reason: 'tokenize 应产出 model_inputs.pkl');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
