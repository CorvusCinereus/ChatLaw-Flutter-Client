// @file ui_layout_test.dart
// @brief 布局冒烟测试：各页面在手机 / 平板尺寸下渲染不报错（无溢出），关键元素存在
//
// 说明：Flutter 在布局溢出时会抛出渲染异常并导致测试失败，因此该测试可有效
// 兜住「元素比例失衡 / 溢出」这类问题，无需真机即可回归。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/internal/design.dart';
import 'package:chatlaw/pages/boot_page.dart';
import 'package:chatlaw/pages/chat_page.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:chatlaw/pages/server_page.dart';
import 'package:chatlaw/pages/setting_page.dart';
import 'package:chatlaw/pages/start_page.dart';
import 'package:chatlaw/services/chat_pipeline.dart';
import 'package:chatlaw/services/inference_client.dart';

const _phone = Size(390, 844);
const _tablet = Size(1100, 800);

AppConfig _config() => AppConfig(
      const TextStyle(fontSize: 14),
      [
        ServerConfig('默认', 'http://localhost:8080'),
        ServerConfig('备用服务器', 'http://192.168.1.100:9000'),
      ],
      [],
      [],
    );

Widget _wrap(Widget child, AppConfig config) =>
    MaterialApp(theme: AppTheme.build(config), home: child);

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

void main() {
  final config = _config();

  setUp(() {
    // 布局测试不触网：注入始终成功、立即返回的假推理客户端
    InferenceClient.debugOverride = _StubInferenceClient();
  });

  tearDown(() {
    InferenceClient.debugOverride = null;
  });

  testWidgets('开始页在手机 / 平板尺寸下不溢出', (tester) async {
    for (final size in [_phone, _tablet]) {
      _setSize(tester, size);
      await tester.pumpWidget(
        _wrap(
          StartPage(
            config: config,
            setPage: (PageIndex page, {String? serverName}) {},
            addServer: (name, address) {},
            removeServer: (name) {},
          ),
          config,
        ),
      );
      await tester.pumpAndSettle();

      // 先断言无异常：这样一旦 body 构建失败能直接看到真实异常
      expect(tester.takeException(), isNull, reason: '$size 下不应有异常');
      expect(find.text('ChatLaw'), findsOneWidget);
      expect(find.text('选择服务器配置'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('添加服务器'), findsOneWidget);
    }
  });

  testWidgets('启动页在手机 / 平板尺寸下不溢出', (tester) async {
    for (final size in [_phone, _tablet]) {
      _setSize(tester, size);
      await tester.pumpWidget(
        _wrap(
          BootPage(
            progress: 0.42,
            message: '正在解包并初始化内嵌 Python 服务',
            detail: '首次启动可能需要几分钟，请保持等待',
            onRetry: () {},
          ),
          config,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ChatLaw'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size 下不应有异常');
    }
  });

  testWidgets('启动页错误态在手机尺寸下不溢出', (tester) async {
    _setSize(tester, _phone);
    await tester.pumpWidget(
      _wrap(
        BootPage(
          progress: 0.9,
          message: '内嵌 Python 服务仍未就绪',
          detail: '请检查模拟器/设备日志后重试',
          error: '等待约 80 秒后仍无法连接内嵌 Python 服务（127.0.0.1:18765）。',
          onRetry: () {},
        ),
        config,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('聊天页在手机 / 平板尺寸下不溢出', (tester) async {
    ChatPipeline.debugOverride = _IdlePipeline();
    addTearDown(() => ChatPipeline.debugOverride = null);

    for (final size in [_phone, _tablet]) {
      _setSize(tester, size);
      await tester.pumpWidget(
        _wrap(
          ChatPage(
            appConfig: config,
            serverName: '默认',
            setPage: (PageIndex page, {String? serverName}) {},
            addHistory: (history) {},
            removeHistory: (name) {},
            addCache: (cache) {},
            renameCache: (oldName, newName) {},
          ),
          config,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('未命名对话'), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size 下不应有异常');
    }
  });

  testWidgets('聊天页发送后（含进度条）不溢出', (tester) async {
    ChatPipeline.debugOverride = _IdlePipeline();
    addTearDown(() => ChatPipeline.debugOverride = null);

    _setSize(tester, _phone);
    await tester.pumpWidget(
      _wrap(
        ChatPage(
          appConfig: config,
          serverName: '默认',
          setPage: (PageIndex page, {String? serverName}) {},
          addHistory: (history) {},
          removeHistory: (name) {},
          addCache: (cache) {},
          renameCache: (oldName, newName) {},
        ),
        config,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '因过失导致宿舍楼失火应承担什么责任？');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 进度条常驻：四步标签应可见
    expect(find.text('RAG检索'), findsOneWidget);
    expect(find.text('推理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务器页在手机 / 平板尺寸下不溢出', (tester) async {
    for (final size in [_phone, _tablet]) {
      _setSize(tester, size);
      await tester.pumpWidget(
        _wrap(
          ServerPage(
            config: config,
            subPage: false,
            addServer: (name, address) {},
            removeServer: (name) {},
            setPage: (PageIndex page, {String? serverName}) {},
            onBack: () {},
          ),
          config,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('添加服务器'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size 下不应有异常');
    }
  });

  testWidgets('服务器编辑态（可删除）在手机尺寸下不溢出', (tester) async {
    _setSize(tester, _phone);
    await tester.pumpWidget(
      _wrap(
        ServerPage(
          config: config,
          serverName: '默认',
          subPage: true,
          addServer: (name, address) {},
          removeServer: (name) {},
          setPage: (PageIndex page, {String? serverName}) {},
          onBack: () {},
        ),
        config,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑服务器'), findsOneWidget);
    expect(find.text('删除该服务器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页在手机 / 平板尺寸下不溢出', (tester) async {
    for (final size in [_phone, _tablet]) {
      _setSize(tester, size);
      await tester.pumpWidget(
        _wrap(
          SettingPage(
            appConfig: config,
            serverName: '默认',
            addServer: (name, address) {},
            removeServer: (name) {},
            setPage: (PageIndex page, {String? serverName}) {},
            onBack: () {},
          ),
          config,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('服务器'), findsWidgets);
      expect(tester.takeException(), isNull, reason: '$size 下不应有异常');
    }
  });
}

/// 立即完成、不返回法条的假流水线（布局测试用）
class _IdlePipeline extends ChatPipeline {
  _IdlePipeline()
      : super(pythonExe: 'n/a', appDataDir: 'n/a', repoRoot: 'n/a');

  @override
  Future<List<RagDoc>> runRag(String question) async => [];

  @override
  Future<void> runBuild() async {}

  @override
  Future<Uint8List> runTokenize() async => Uint8List(0);
}

/// 假推理客户端：布局测试不触网
class _StubInferenceClient extends InferenceClient {
  _StubInferenceClient() : super(host: 'stub');

  @override
  Future<String?> checkHealth() async => null;

  @override
  Stream<String> infer(List<int> pickledInputs) async* {
    yield '（布局测试占位回答）';
  }
}
