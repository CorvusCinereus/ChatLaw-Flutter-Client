/**
 * @file home_page.dart
 * @brief HomePage（配置装载、启动引导与页面切换）
 * @author CorvusCinereus
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../internal/app_state.dart';
import '../internal/config.dart';
import '../internal/design.dart';
import '../services/chat_pipeline.dart';
import 'boot_page.dart';
import 'chat_page.dart';
import 'dialog.dart';
import 'page_index.dart';
import 'server_page.dart';
import 'setting_page.dart';
import 'start_page.dart';

/// 导航栈条目：页码 + 该页所需的服务器名
class _NavEntry {
  final PageIndex page;
  final String? serverName;

  const _NavEntry(this.page, this.serverName);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppConfig? _config;

  /// 当前渲染的页面；启动阶段为引导页
  Widget? _body;
  Key _pageKey = const ValueKey('boot');

  /// 启动阶段（显示引导页、各页不自带 Scaffold）
  bool _bootPhase = true;
  bool _configLoaded = false;
  bool _serviceReady = false;
  bool _bootComplete = false;
  bool _bootFailed = false;
  String _bootMessage = '正在准备启动环境';
  String? _bootDetail;
  String? _bootError;
  double _bootProgress = 0.05;
  Timer? _progressTimer;

  /// 导航栈
  final List<_NavEntry> _stack = [];
  _NavEntry? _current;

  @override
  void initState() {
    super.initState();
    _startBootSequence();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 启动引导
  // ---------------------------------------------------------------------------

  void _startBootSequence() {
    _configLoaded = false;
    _serviceReady = false;
    _bootFailed = false;
    _bootComplete = false;
    _bootProgress = 0.05;
    _bootMessage = '正在解包并初始化内嵌 Python 服务';
    _bootDetail = '首次启动可能需要几分钟，请保持等待';
    _bootError = null;
    _body = _buildBootPage();
    _pageKey = UniqueKey();

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!mounted || _bootComplete) {
        timer.cancel();
        return;
      }
      final target = _serviceReady ? 1.0 : 0.92;
      final step = _serviceReady ? 0.08 : 0.015;
      final next = (_bootProgress + step).clamp(0.05, target);
      if (next != _bootProgress) {
        setState(() {
          _bootProgress = next;
          _body = _buildBootPage();
        });
      }
    });

    _loadConfigAsync();
    _waitForPythonService();
  }

  Widget _buildBootPage() => BootPage(
        progress: _bootProgress,
        message: _bootMessage,
        detail: _bootDetail,
        error: _bootError,
        onRetry: _retryBoot,
      );

  Future<void> _loadConfigAsync() async {
    try {
      final path = await getApplicationDocumentsDirectory();
      final dir = Directory('${path.path}/ChatLaw');
      if (await dir.exists()) {
        final file = File('${dir.path}/config.json');
        if (await file.exists()) {
          final jsonText = await file.readAsString();
          _config = AppConfig.fromJson(jsonDecode(jsonText));
        } else {
          _config = AppConfig.defaultConfig();
        }
      } else {
        await dir.create(recursive: true);
        _config = AppConfig.defaultConfig();
      }
    } catch (e) {
      _config = AppConfig.defaultConfig();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAlertDialog(
          context,
          '配置文件损坏，已重置为默认配置。\n$e',
          textStyle: _config?.textStyle,
        );
      });
    }

    // 主题（字号/字体族）随配置刷新
    configNotifier.value = _config;
    _configLoaded = true;
    _finishBootIfReady();
  }

  Future<void> _waitForPythonService() async {
    final pipeline = ChatPipeline();
    const maxAttempts = 40;
    const delay = Duration(seconds: 2);

    for (var attempt = 0;
        attempt < maxAttempts && mounted && !_bootComplete;
        attempt++) {
      final ready = await pipeline.isPythonServiceReady();
      if (ready) {
        _serviceReady = true;
        _finishBootIfReady();
        return;
      }
      await Future<void>.delayed(delay);
    }

    if (!mounted || _bootComplete) return;
    _bootFailed = true;
    setState(() {
      _bootError = '等待约 80 秒后仍无法连接内嵌 Python 服务（127.0.0.1:18765）。';
      _body = _buildBootPage();
    });
  }

  void _finishBootIfReady() {
    if (_bootComplete || !_configLoaded || !_serviceReady || _config == null) {
      return;
    }
    _bootComplete = true;
    _bootFailed = false;
    _progressTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _bootPhase = false;
      _stack.clear();
      _current = null;
      _setPageInternal(PageIndex.start, null);
    });
  }

  void _retryBoot() {
    if (!_bootFailed) return;
    _startBootSequence();
  }

  // ---------------------------------------------------------------------------
  // 导航
  // ---------------------------------------------------------------------------

  /// 供子页面调用的导航入口
  void _setPage(PageIndex page, {String? serverName}) {
    setState(() => _setPageInternal(page, serverName));
  }

  void _setPageInternal(PageIndex page, String? serverName) {
    final entry = _NavEntry(page, serverName);
    final current = _current;
    if (current != null &&
        !(current.page == page && current.serverName == serverName)) {
      _stack.add(current);
    }
    _current = entry;
    _body = _buildPage(page, serverName);
    _pageKey = ValueKey('${page.name}:${serverName ?? ''}');
  }

  /// 返回上一页；栈空时不处理（由 PopScope 交给系统退出）
  void _goBack() {
    if (_stack.isEmpty) return;
    setState(() {
      final entry = _stack.removeLast();
      _current = entry;
      _body = _buildPage(entry.page, entry.serverName);
      _pageKey = ValueKey('${entry.page.name}:${entry.serverName ?? ''}');
    });
  }

  Widget _buildPage(PageIndex page, String? serverName) {
    switch (page) {
      case PageIndex.start:
        return StartPage(
          config: _config!,
          setPage: _setPage,
          addServer: _addServer,
          removeServer: _removeServer,
        );
      case PageIndex.chat:
        return ChatPage(
          appConfig: _config!,
          serverName: serverName ?? '',
          setPage: _setPage,
          addHistory: _addHistory,
          removeHistory: _removeHistory,
          addCache: _addCache,
          renameCache: _renameCache,
        );
      case PageIndex.server:
        return ServerPage(
          config: _config!,
          serverName: serverName,
          subPage: serverName != null,
          addServer: _addServer,
          removeServer: _removeServer,
          setPage: _setPage,
          onBack: _goBack,
        );
      case PageIndex.setting:
        return SettingPage(
          appConfig: _config!,
          serverName: serverName,
          addServer: _addServer,
          removeServer: _removeServer,
          setPage: _setPage,
          onBack: _goBack,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // 配置读写
  // ---------------------------------------------------------------------------

  void _addServer(String name, String address) {
    if (name.isEmpty || address.isEmpty) {
      showAlertDialog(
        context,
        '请完整填写配置信息',
        textStyle: _config?.textStyle,
      );
      return;
    }
    final index = _config!.serverConfigs.indexWhere((e) => e.name == name);
    if (index != -1) {
      _config!.serverConfigs[index].address = address;
    } else {
      _config!.serverConfigs.add(ServerConfig(name, address));
    }
    _saveConfig();
  }

  void _removeServer(String name) {
    _config!.serverConfigs.removeWhere((element) => element.name == name);
    _config!.lawCaches.removeWhere((element) => element.name == name);
    _saveConfig();
  }

  void _addHistory(Map<String, dynamic> history) {
    _config!.history.removeWhere(
      (element) => element['name'] == history['name'],
    );
    _config!.history.add(history);
    _saveConfig();
  }

  void _removeHistory(String name) {
    _config!.history.removeWhere((element) => element['name'] == name);
    _config!.lawCaches.removeWhere((element) => element.name == name);
    _saveConfig();
  }

  void _addCache(LawCache cache) {
    _config!.lawCaches.removeWhere((element) => element.name == cache.name);
    _config!.lawCaches.add(cache);
    _saveConfig();
  }

  void _renameCache(String oldName, String newName) {
    final index = _config!.lawCaches.indexWhere((e) => e.name == oldName);
    if (index != -1) _config!.lawCaches[index].name = newName;
    _saveConfig();
  }

  Future<void> _saveConfig() async {
    try {
      final path = await getApplicationDocumentsDirectory();
      final dir = Directory('${path.path}/ChatLaw');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/config.json');
      await file.writeAsString(jsonEncode(_config!.toJson()));
    } catch (e) {
      debugPrint('[chatlaw] 保存配置失败: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 界面
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_bootPhase) {
      return Scaffold(
        body: SafeArea(
          child: _body ?? const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return PopScope(
      canPop: _stack.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: AnimatedSwitcher(
        duration: AppDuration.normal,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: _pageKey,
          child: _body ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
