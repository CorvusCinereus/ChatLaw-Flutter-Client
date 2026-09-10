// @file chat_page_flow_test.dart
// @brief 聊天页发送流程 widget 测试：真实数据落位（假流水线 + 假推理客户端注入）
//
// 验证：发送问题后 → user 气泡出现 → assistant 流式回答出现 →
//       打开「检索法条」底部抽屉可见检索到的法条标题 →
//       检索缓存与历史经回调持久化；流水线失败时渲染错误气泡。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/internal/design.dart';
import 'package:chatlaw/pages/chat_page.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:chatlaw/services/chat_pipeline.dart';
import 'package:chatlaw/services/inference_client.dart';

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
  Future<Uint8List> runTokenize() async => Uint8List.fromList([1, 2, 3, 4]);
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
  Future<Uint8List> runTokenize() async => Uint8List(0);
}

/// 假推理客户端：健康检查通过，分两块产出文本
class _FakeInferenceClient extends InferenceClient {
  _FakeInferenceClient() : super(host: 'test-host');

  @override
  Future<String?> checkHealth() async => null;

  @override
  Stream<String> infer(List<int> pickledInputs) async* {
    yield '根据《中华人民共和国消防法》第五十一条';
    yield '，应承担相应责任。';
  }
}

/// 可控推理客户端：由测试决定何时推送增量，用于验证"流式"与"中止"
class _ControlledInferenceClient extends InferenceClient {
  _ControlledInferenceClient() : super(host: 'test-host');

  final StreamController<String> controller = StreamController<String>();

  @override
  Future<String?> checkHealth() async => null;

  @override
  Stream<String> infer(List<int> pickledInputs) => controller.stream;

  void push(String text) => controller.add(text);

  Future<void> finish() => controller.close();
}

void main() {
  late AppConfig appConfig;
  late List<Map<String, dynamic>> savedHistory;
  late List<LawCache> savedCaches;

  setUp(() {
    ChatPipeline.debugOverride = _FakePipeline();
    InferenceClient.debugOverride = _FakeInferenceClient();
    appConfig = AppConfig(
      const TextStyle(fontSize: 14),
      [ServerConfig('默认', '192.168.137.99')],
      [],
      [],
    );
    savedHistory = [];
    savedCaches = [];
  });

  tearDown(() {
    ChatPipeline.debugOverride = null;
    InferenceClient.debugOverride = null;
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

  testWidgets('发送问题后展示真实检索法条与服务端流式回答', (tester) async {
    await tester.pumpWidget(buildPage());

    // 输入并发送问题
    await tester.enterText(
      find.byType(TextField),
      '因过失导致宿舍楼失火应承担什么责任？',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(); // 触发 _sendMessage
    await tester.pump(const Duration(seconds: 1)); // 等流水线与推理完成

    // user 气泡出现
    expect(
      find.text('因过失导致宿舍楼失火应承担什么责任？'),
      findsOneWidget,
      reason: '用户消息应以气泡渲染',
    );

    // assistant 流式回答气泡出现
    expect(
      find.textContaining('应承担相应责任'),
      findsOneWidget,
      reason: '推理步骤应渲染服务端流式回答',
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

  testWidgets('回答按流式增量逐步渲染（非一次性出现）', (tester) async {
    final client = _ControlledInferenceClient();
    InferenceClient.debugOverride = client;
    // 不能直接传 close（teardown 会 await 它，而订阅已被页面取消 → 该 future
    // 不会完成，导致测试挂死），故 fire-and-forget。
    addTearDown(() => unawaited(client.controller.close()));

    await tester.pumpWidget(buildPage());
    await tester.enterText(find.byType(TextField), '问题');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // 等检索/构建/分词

    // 首个增量到达前显示生成中占位
    expect(find.text('正在生成…'), findsOneWidget, reason: '等待首块时应显示生成中占位');

    client.push('第一段');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.textContaining('第一段'), findsOneWidget, reason: '增量到达后应尽快渲染');
    expect(find.textContaining('第二段'), findsNothing, reason: '尚未到达的内容不应出现');
    expect(find.text('正在生成…'), findsNothing, reason: '占位应被真实内容替换');

    client.push('第二段');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.textContaining('第一段第二段'), findsOneWidget, reason: '后续增量应追加渲染');

    // 注意：不能 await controller.close()——在 testWidgets 中等待它的 future
    // 而不 pump 会挂住；这里 fire-and-forget 后再 pump 让 done 事件送达。
    unawaited(client.finish());
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(find.textContaining('第一段第二段'), findsOneWidget);
  });

  testWidgets('生成中可停止：保留已收到内容并标注中止', (tester) async {
    final client = _ControlledInferenceClient();
    InferenceClient.debugOverride = client;
    // 不能直接传 close（teardown 会 await 它，而订阅已被页面取消 → 该 future
    // 不会完成，导致测试挂死），故 fire-and-forget。
    addTearDown(() => unawaited(client.controller.close()));

    await tester.pumpWidget(buildPage());
    await tester.enterText(find.byType(TextField), '问题');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    client.push('已生成的部分');
    await tester.pump(const Duration(milliseconds: 120));

    // 生成中：发送键被停止键取代
    expect(find.byIcon(Icons.stop), findsOneWidget, reason: '生成中应可停止');
    expect(find.byIcon(Icons.send), findsNothing);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(find.textContaining('已生成的部分'), findsOneWidget, reason: '已收到的内容应保留');
    expect(find.textContaining('已中止生成'), findsOneWidget, reason: '应标注已中止');
    expect(find.byIcon(Icons.send), findsOneWidget, reason: '结束后恢复发送键');
  });
}
