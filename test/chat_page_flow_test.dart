// @file chat_page_flow_test.dart
// @brief 聊天页发送流程 widget 测试：真实数据落位（假流水线注入）
//
// 验证：发送问题后 → user 气泡出现 → assistant 虚拟回答出现 →
//       打开「检索法条」底部抽屉可见检索到的法条标题 →
//       检索缓存与历史经回调持久化；流水线失败时渲染错误气泡。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/internal/design.dart';
import 'package:chatlaw/pages/chat_page.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:chatlaw/services/chat_pipeline.dart';

/// 假流水线：返回两条固定法条，立即完成各阶段
class _FakePipeline extends ChatPipeline {
  _FakePipeline()
      : super(pythonExe: 'n/a', appDataDir: 'n/a', repoRoot: 'n/a');

  static final docs = [
    RagDoc(
      lawName: '中华人民共和国消防法',
      article: '第五十一条',
      content: '消防救援机构有权根据需要封闭火灾现场。',
      source: 'exact',
    ),
    RagDoc(
      lawName: '中华人民共和国民法典',
      article: '第一千二百三十九条',
      content: '占有或者使用易燃、易爆等高度危险物造成他人损害的，占有人或者使用人应当承担侵权责任。',
      source: 'faiss',
    ),
  ];

  @override
  Future<List<RagDoc>> runRag(String question) async => docs;

  @override
  Future<void> runBuild() async {}

  @override
  Future<void> runTokenize() async {}
}

/// 失败流水线：runRag 直接抛异常
class _BrokenPipeline extends ChatPipeline {
  _BrokenPipeline()
      : super(pythonExe: 'n/a', appDataDir: 'n/a', repoRoot: 'n/a');

  @override
  Future<List<RagDoc>> runRag(String question) async {
    throw PipelineException('Python 解释器不存在: n/a');
  }

  @override
  Future<void> runBuild() async {}

  @override
  Future<void> runTokenize() async {}
}

void main() {
  late AppConfig appConfig;
  late List<Map<String, dynamic>> savedHistory;
  late List<LawCache> savedCaches;

  setUp(() {
    ChatPipeline.debugOverride = _FakePipeline();
    appConfig = AppConfig(
      const TextStyle(fontSize: 14),
      [ServerConfig('默认', 'http://localhost:8080')],
      [],
      [],
    );
    savedHistory = [];
    savedCaches = [];
  });

  tearDown(() {
    ChatPipeline.debugOverride = null;
  });

  Widget buildPage() {
    return MaterialApp(
      theme: AppTheme.build(appConfig),
      home: ChatPage(
        appConfig: appConfig,
        serverName: '默认',
        setPage: (PageIndex page, {String? serverName}) {},
        addHistory: (history) => savedHistory.add(history),
        removeHistory: (name) {},
        addCache: (cache) => savedCaches.add(cache),
        renameCache: (oldName, newName) {},
      ),
    );
  }

  testWidgets('发送问题后展示真实检索法条与虚拟回答', (tester) async {
    await tester.pumpWidget(buildPage());

    // 输入并发送问题
    await tester.enterText(
      find.byType(TextField),
      '因过失导致宿舍楼失火应承担什么责任？',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(); // 触发 _sendMessage
    await tester.pump(const Duration(seconds: 1)); // 等流水线跑完（含推理延时）

    // user 气泡出现
    expect(
      find.text('因过失导致宿舍楼失火应承担什么责任？'),
      findsOneWidget,
      reason: '用户消息应以气泡渲染',
    );

    // assistant 虚拟回答气泡出现
    expect(
      find.textContaining('虚拟推理输出'),
      findsOneWidget,
      reason: '推理步骤应渲染虚拟回答气泡',
    );

    // 打开「检索法条」底部抽屉，确认 RAG 命中的法条标题
    await tester.tap(find.byTooltip('检索法条'));
    await tester.pumpAndSettle();
    expect(
      find.text('《中华人民共和国消防法》第五十一条'),
      findsOneWidget,
      reason: 'RAG 命中的法条标题应出现在检索抽屉中',
    );
    expect(
      find.text('《中华人民共和国民法典》第一千二百三十九条'),
      findsOneWidget,
    );

    // 检索缓存经回调持久化（含真实条文）
    expect(savedCaches, hasLength(1));
    expect(savedCaches.first.laws, hasLength(2));
    expect(savedCaches.first.laws.first, '《中华人民共和国消防法》第五十一条');

    // 历史消息持久化（user + assistant）
    expect(savedHistory, hasLength(1));
    final roles =
        (savedHistory.first['history'] as List).map((e) => e['role']).toList();
    expect(roles, ['user', 'assistant']);
  });

  testWidgets('流水线失败时展示错误气泡', (tester) async {
    ChatPipeline.debugOverride = _BrokenPipeline();
    await tester.pumpWidget(buildPage());

    await tester.enterText(find.byType(TextField), '测试问题');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.textContaining('流水线执行失败'),
      findsOneWidget,
      reason: '失败时应渲染 assistant 错误气泡',
    );
  });
}
