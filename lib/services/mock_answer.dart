// @file mock_answer.dart
// @brief 虚拟推理回答生成（推理服务器尚未接入时的占位输出）
//
// 生成纯文本（聊天气泡不支持 Markdown）。内容引用真实 RAG 检索到的
// 法律条文，并明确标注为虚拟输出；接入推理服务器后此文件可废弃。

import 'package:chatlaw/services/chat_pipeline.dart';

/// 生成虚拟回答文本
String buildVirtualAnswer(String query, List<RagDoc> docs) {
  final buffer = StringBuffer();

  buffer.writeln('（虚拟推理输出 · 推理服务器尚未接入，以下为演示文本）');
  buffer.writeln();

  if (docs.isEmpty) {
    buffer.writeln('未检索到直接相关的法律条文。');
  } else {
    buffer.writeln('针对问题「$query」，已检索到 ${docs.length} 条相关法律条文：');
    final shown = docs.length > 3 ? 3 : docs.length;
    for (var i = 0; i < shown; i++) {
      buffer.writeln('${i + 1}. 《${docs[i].lawName}》${docs[i].article}');
    }
    buffer.writeln();
    buffer.writeln('结合上述条文，该问题需要根据具体事实与条文要件综合判断；');
    buffer.writeln('接入推理服务器后，此处将给出模型生成的详细分析结论。');
  }

  return buffer.toString();
}
