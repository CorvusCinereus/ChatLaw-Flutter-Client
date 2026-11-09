/**
 * @file chat_page.dart
 * @brief 聊天页面：提问 → RAG 检索 → 构建提示词 → 分词 → 虚拟回答
 * @author CorvusCinereus
 */

<<<<<<< HEAD
import 'dart:io' show File, Platform;
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
=======
import 'dart:async';
import 'dart:math' as math;

>>>>>>> 7417a5176b1f7f89b37c6e3094d5140f108b7e75
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../internal/config.dart';
import '../internal/design.dart';
import '../services/chat_pipeline.dart';
import '../services/inference_client.dart';
import 'dialog.dart';
import 'page_index.dart';

/// 流水线步骤（与 _step 的 0..4 对应）
const List<String> _kSteps = ['RAG检索', '构建提示词', '分词', '推理'];

/// 等待模型首个增量时的占位文案
const String _kGeneratingHint = '正在生成…';

/// 流式刷新节流（毫秒）：过密会掉帧，过疏会显得不"流式"
const int _kStreamFlushMs = 60;

/// 「回车发送」意图（多行输入框默认把回车当换行，这里显式改绑为发送）
class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class ChatPage extends StatefulWidget {
  final AppConfig appConfig;
  final String serverName;
  final Function(PageIndex page, {String? serverName}) setPage;
  final Function(Map<String, dynamic> history) addHistory;
  final Function(String name) removeHistory;
  final Function(LawCache cache) addCache;
  final Function(String oldName, String newName) renameCache;

  const ChatPage({
    super.key,
    required this.appConfig,
    required this.serverName,
    required this.setPage,
    required this.addHistory,
    required this.removeHistory,
    required this.addCache,
    required this.renameCache,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  int _serverIndex = -1;
  String _historyName = '未命名对话';
  List<Map<String, dynamic>> _history = [];
  List<String> _caches = [];
  List<String> _details = [];

  /// 流水线进度：-1 空闲，0..4 已完成步数
  int _step = -1;
  bool _pipelineRunning = false;

  bool _recording = false;
  AudioRecorder? _record;

  /// 用户是否请求中止本轮生成
  bool _stopRequested = false;

  /// 正在进行的推理流（用于中止）
  StreamSubscription<String>? _inferSub;
  Completer<void>? _inferCompleter;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _serverIndex = widget.appConfig.serverConfigs.indexWhere(
      (element) => element.name == widget.serverName,
    );
    if (_serverIndex == -1) {
      // 首帧之后再弹窗，避免在 initState 中调用 showDialog。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAlertDialog(
          context,
          '服务器「${widget.serverName}」不存在，请重新选择。',
          textStyle: widget.appConfig.textStyle,
        );
        widget.setPage(PageIndex.start);
      });
    }
  }

  @override
  void dispose() {
    _inferSub?.cancel();
    _record?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 消息与流水线
  // ---------------------------------------------------------------------------

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppDuration.normal,
        curve: Curves.easeOut,
      );
    });
  }

  void _onSendPressed() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _pipelineRunning || _recording) return;
    _messageController.clear();
    _sendMessage(text);
  }

  void _sendMessage(String message) {
    setState(() {
      if (_historyName == '未命名对话') {
        final name = message.length < 7 ? message : message.substring(0, 6);
        _historyName = widget.appConfig.history.any((e) => e['name'] == name)
            ? '$name#'
            : name;
      }
      _history.add({'role': 'user', 'content': message});
    });
    _scrollToBottomSoon();
    _startProgress(message);
  }

  Future<void> _startProgress(String question) async {
    if (_pipelineRunning) return;
    _pipelineRunning = true;
    _stopRequested = false;
    setState(() => _step = 0);

    final pipeline = ChatPipeline.debugOverride ?? ChatPipeline();
    List<RagDoc> docs = [];
    var assistantIndex = -1;

    try {
<<<<<<< HEAD
      _record = AudioRecorder();
      final dir = await getApplicationCacheDirectory();
      final outputPath = "${dir.path}/output.wav";
      if (await _record!.hasPermission()) {
        await _record!.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 256000,
          ),
          path: outputPath,
        );
      } else {
        showAlertDialog(
          context,
          "没有录音权限!",
          title: Icon(Icons.error),
          textStyle: widget._appConfig.textStyle,
        );
=======
      // 步骤 1：真实 RAG 检索
      docs = await pipeline.runRag(question);
      if (!mounted) return;
      if (_abortIfRequested()) return;
      setState(() {
        _caches = docs.map((d) => d.title).toList();
        _details = docs.map((d) => d.content).toList();
        _step = 1;
      });

      // 步骤 2：构建 prompt
      await pipeline.runBuild();
      if (!mounted) return;
      if (_abortIfRequested()) return;
      setState(() => _step = 2);

      // 步骤 3：分词，得到发给推理服务器的 pickle 负载
      final payload = await pipeline.runTokenize();
      if (!mounted) return;
      if (_abortIfRequested()) return;
      setState(() => _step = 3);

      // 步骤 4：真实推理（流式）
      final client =
          InferenceClient.debugOverride ?? InferenceClient(host: _serverHost);

      final healthError = await client.checkHealth();
      if (!mounted) return;
      if (_abortIfRequested()) return;
      if (healthError != null) {
        throw PipelineException(healthError);
      }

      // 先占位一条 assistant 消息，随后按流式增量刷新
      setState(() {
        _history.add({'role': 'assistant', 'content': _kGeneratingHint});
        assistantIndex = _history.length - 1;
      });
      _scrollToBottomSoon();

      final buffer = StringBuffer();

      void flush() {
        if (!mounted) return;
        setState(() {
          _history[assistantIndex]['content'] =
              buffer.isEmpty ? _kGeneratingHint : buffer.toString();
        });
        _scrollToBottomSoon();
      }

      // 用 Timer 合并刷新：密集增量下最多每 _kStreamFlushMs 刷新一次，
      // 既避免逐块 setState 掉帧，又不依赖墙钟（可被测试稳定推进）。
      Timer? flushTimer;
      void scheduleFlush() {
        if (flushTimer != null) return;
        flushTimer = Timer(const Duration(milliseconds: _kStreamFlushMs), () {
          flushTimer = null;
          flush();
        });
      }

      // 用 listen（而非 await for）以便中止：取消订阅会让客户端向服务端发 STOP
      final completer = Completer<void>();
      _inferCompleter = completer;
      _inferSub = client.infer(payload).listen(
        (delta) {
          buffer.write(delta);
          scheduleFlush();
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      try {
        await completer.future;
      } finally {
        flushTimer?.cancel();
        flushTimer = null;
        final sub = _inferSub;
        _inferSub = null;
        _inferCompleter = null;
        // 不 await：流正常结束时 async* 生成器的 cancel() future 不保证完成，
        // 而此处也无需等待——取消本身已足够（中止场景会触发客户端发送 STOP）。
        if (sub != null) unawaited(sub.cancel());
      }

      if (!mounted) return;
      final aborted = _stopRequested;
      final text = buffer.toString();
      setState(() {
        if (aborted) {
          _history[assistantIndex]['content'] =
              text.isEmpty ? '（已中止生成）' : '$text\n\n（已中止生成）';
        } else {
          _history[assistantIndex]['content'] =
              text.isEmpty ? '（模型未返回内容）' : text;
        }
        _step = 4;
      });
      _scrollToBottomSoon();

      widget.addHistory({'name': _historyName, 'history': _history});
      if (_caches.isNotEmpty) {
        widget.addCache(LawCache(_historyName, _caches, _details));
>>>>>>> 7417a5176b1f7f89b37c6e3094d5140f108b7e75
      }
    } catch (e) {
      if (!mounted) return;
      if (assistantIndex == -1) {
        // 推理尚未开始（检索/构建/分词/连通性失败）
        setState(() {
          _history.add({
            'role': 'assistant',
            'content': '⚠️ 流水线执行失败：$e',
          });
        });
      } else {
        // 推理中途失败：保留已收到的内容并标注中断
        final partial = _history[assistantIndex]['content'] as String? ?? '';
        final hasText = partial.isNotEmpty && partial != _kGeneratingHint;
        setState(() {
          _history[assistantIndex]['content'] = hasText
              ? '$partial\n\n⚠️ 推理中断：$e'
              : '⚠️ 推理失败：$e';
        });
      }
      _scrollToBottomSoon();
      widget.addHistory({'name': _historyName, 'history': _history});
    } finally {
      _inferSub = null;
      _inferCompleter = null;
      if (mounted) setState(() => _pipelineRunning = false);
    }
  }

<<<<<<< HEAD
  void _stopRecord() async {
    final _ = await _record!.stop();
  }

  Future<String?> _voiceToText() async {
    final Map<String, String> envVars = Platform.environment;
    final apiKey = envVars['CHATLAW_VOICE_API_KEY'];
    final secretKey = envVars['CHATLAW_VOICE_SECRET_KEY'];

    final cuid = widget._appConfig.uuid;
    final int devPid = 1537;
    final dir = await getApplicationCacheDirectory();
    final pcmFilePath = "${dir.path}/output.wav";
    final dio = Dio();

    try {
      final tokenResponse = await dio.post(
        'http://aip.baidubce.com/oauth/2.0/token',
        data: {
          'grant_type': 'client_credentials',
          'client_id': apiKey,
          'client_secret': secretKey,
        },
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final tokenData = tokenResponse.data;

      if (!tokenData.containsKey('access_token')) {
        showAlertDialog(
          context,
          '获取 Token 失败：${tokenData}',
          title: const Icon(Icons.error),
          textStyle: widget._appConfig.textStyle,
        );
        return "";
      }

      final String token = tokenData['access_token'];

      final File audioFile = File(pcmFilePath);
      if (!await audioFile.exists()) {
        showAlertDialog(
          context,
          '文件不存在：$pcmFilePath',
          title: const Icon(Icons.error),
          textStyle: widget._appConfig.textStyle,
        );
        return "";
      }

      // 获取文件大小
      Uint8List speechData = await audioFile.readAsBytes();

      final int length = speechData.length;

      final Map<String, dynamic> queryParams = {
        'cuid': cuid,
        'token': token,
        'dev_pid': devPid,
      };

      final Map<String, dynamic> headers = {
        'Content-Type': 'audio/pcm; rate=16000',
        'Content-Length': length,
      };

      final stopwatch = Stopwatch()..start();

      final response = await dio.post(
        'http://vop.baidu.com/server_api',
        queryParameters: queryParams,
        data: speechData,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      stopwatch.stop();

      final result = response.data;
      final int errNo = result['err_no'] ?? -1;

      if (errNo == 0) {
        final List? resultList = result['result'];

        if (resultList != null && resultList.isNotEmpty) {
          final String recognizedText = resultList[0].toString();
          return recognizedText;
        } else {
          showAlertDialog(
            context,
            '识别结果为空',
            title: const Icon(Icons.error),
            textStyle: widget._appConfig.textStyle,
          );
        }
      } else {
        final String errMsg = result['err_msg'] ?? '未知错误';
        showAlertDialog(
          context,
          '识别失败：$errMsg (错误码: $errNo)',
          title: const Icon(Icons.error),
          textStyle: widget._appConfig.textStyle,
        );
      }
    } on DioException catch (e) {
      showAlertDialog(
        context,
        '网络请求失败：${e.message}',
        title: const Icon(Icons.error),
        textStyle: widget._appConfig.textStyle,
      );
    } catch (e) {
      showAlertDialog(
        context,
        '未知错误',
        title: const Icon(Icons.error),
        textStyle: widget._appConfig.textStyle,
      );
    }
    return null;
=======
  /// 中止当前生成。
  ///
  /// 取消推理流会触发客户端向服务端发送一次 STOP（见 InferenceClient.infer 的
  /// finally），从而让服务端停止继续生成。
  void _stopGeneration() {
    if (!_pipelineRunning) return;
    _stopRequested = true;
    final completer = _inferCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _inferSub?.cancel();
>>>>>>> 7417a5176b1f7f89b37c6e3094d5140f108b7e75
  }

  /// 步骤之间检查是否已被中止；是则补一条中止提示并让调用方提前返回
  bool _abortIfRequested() {
    if (!_stopRequested) return false;
    setState(() {
      _history.add({'role': 'assistant', 'content': '（已中止生成）'});
    });
    _scrollToBottomSoon();
    return true;
  }

  /// 当前会话对应的服务器 IP（端口由服务端固定）
  String get _serverHost {
    final servers = widget.appConfig.serverConfigs;
    if (_serverIndex >= 0 && _serverIndex < servers.length) {
      return servers[_serverIndex].host;
    }
    return widget.serverName;
  }

  void _newConversation() {
    setState(() {
      _historyName = '未命名对话';
      _history = [];
      _caches = [];
      _details = [];
      _step = -1;
    });
  }

  Future<void> _openLaws() async {
    if (_caches.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, controller) => _LawsSheet(
          laws: _caches,
          details: _details,
          controller: controller,
          textStyle: widget.appConfig.textStyle,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 录音
  // ---------------------------------------------------------------------------

  Future<void> _toggleRecord() async {
    if (!_recording) {
      try {
        final recorder = AudioRecorder();
        final dir = await getApplicationCacheDirectory();
        if (!await recorder.hasPermission()) {
          if (mounted) {
            showAlertDialog(
              context,
              '没有录音权限，请在系统设置中授予。',
              textStyle: widget.appConfig.textStyle,
            );
          }
          return;
        }
        await recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: '${dir.path}/output.wav',
        );
        setState(() {
          _record = recorder;
          _recording = true;
        });
      } catch (e) {
        if (mounted) {
          showAlertDialog(
            context,
            '启动录音失败：$e',
            textStyle: widget.appConfig.textStyle,
          );
        }
      }
    } else {
      try {
        await _record?.stop();
        await _record?.dispose();
      } catch (_) {
        // 忽略停止/释放异常
      }
      if (!mounted) return;
      setState(() {
        _recording = false;
        _record = null;
      });
      // TODO: 接入语音转文本后替换占位文本
      _sendMessage('一段语音...');
    }
  }

  // ---------------------------------------------------------------------------
  // 历史对话
  // ---------------------------------------------------------------------------

  void _loadConversation(Map<String, dynamic> item) {
    Navigator.of(context).pop(); // 关闭抽屉
    setState(() {
      _historyName = item['name'] ?? '未命名对话';
      _history = (item['history'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final index = widget.appConfig.lawCaches.indexWhere(
        (element) => element.name == _historyName,
      );
      if (index != -1) {
        _caches = widget.appConfig.lawCaches[index].laws;
        _details = widget.appConfig.lawCaches[index].details;
        _step = _caches.isEmpty ? -1 : 4;
      } else {
        _caches = [];
        _details = [];
        _step = -1;
      }
    });
    _scrollToBottomSoon();
  }

  Future<void> _renameConversation(Map<String, dynamic> item) async {
    final controller =
        TextEditingController(text: item['name'] as String? ?? '');
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入新名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.trim().isEmpty) return;

    var target = newName.trim();
    if (widget.appConfig.history.any((e) => e['name'] == target) &&
        target != _historyName) {
      target = '$target#';
    }
    final oldName = _historyName;
    setState(() {
      widget.renameCache(oldName, target);
      _historyName = target;
      item['name'] = target;
    });
    widget.addHistory(item);
  }

  Future<void> _deleteConversation(String title) async {
    final ok = await showAskDialog(
      context,
      '是否删除对话「$title」？',
      destructive: true,
      confirmText: '删除',
      textStyle: widget.appConfig.textStyle,
    );
    if (!ok) return;
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭抽屉
    setState(() {
      if (_historyName == title) _newConversation();
    });
    widget.removeHistory(title);
  }

  // ---------------------------------------------------------------------------
  // 界面
  // ---------------------------------------------------------------------------

  Widget _buildDrawer() {
    final historyList = widget.appConfig.history;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ChatLaw', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text('历史对话', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _newConversation();
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('新对话'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: historyList.isEmpty
                  ? Center(
                      child: Text(
                        '暂无历史记录',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: historyList.length,
                      itemBuilder: (context, index) {
                        final item = historyList[index];
                        final title = item['name'] ?? '未命名对话';
                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline, size: 20),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: title == _historyName,
                          selectedTileColor: AppColors.brandSoft,
                          onTap: () => _loadConversation(item),
                          trailing: PopupMenuButton<String>(
                            tooltip: '更多',
                            icon: const Icon(Icons.more_vert, size: 20),
                            onSelected: (value) {
                              if (value == 'rename') {
                                _renameConversation(item);
                              } else if (value == 'delete') {
                                _deleteConversation(title);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('重命名'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline,
                                      color: AppColors.danger),
                                  title: Text('删除',
                                      style: TextStyle(color: AppColors.danger)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.of(context).pop();
                widget.setPage(PageIndex.setting, serverName: widget.serverName);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(double pad) {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.gavel_outlined, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text('开始你的法律咨询', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '输入问题后，将检索相关法条并生成答复。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubble =
            math.min(constraints.maxWidth * 0.78, AppSizes.bubbleMaxWidth);
        return ListView.separated(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: AppSpacing.lg,
          ),
          itemCount: _history.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _Bubble(
            appConfig: widget.appConfig,
            sender: _history[index]['role'],
            content: _history[index]['content'] ?? '',
            maxWidth: maxBubble,
          ),
        );
      },
    );
  }

  Widget _buildProgressStrip(double pad) {
    if (_step < 0) return const SizedBox.shrink();
    final done = _step >= _kSteps.length;

    return Container(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.md, pad, AppSpacing.sm),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(_kSteps.length, (i) {
              final finished = i < _step;
              final active = i == _step && !done;
              final color = finished || active
                  ? AppColors.brand
                  : AppColors.textTertiary;
              return Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      finished
                          ? Icons.check_circle
                          : (active ? Icons.radio_button_checked : Icons.circle),
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        _kSteps[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                              (widget.appConfig.textStyle.fontSize ?? 14) - 2,
                          color: color,
                          fontWeight:
                              finished || active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: done ? 1.0 : _step / _kSteps.length,
              backgroundColor: AppColors.divider,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(double pad) {
    return Container(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: _recording ? '停止录音' : '按住说话（语音）',
            onPressed: _toggleRecord,
            icon: Icon(
              _recording ? Icons.stop_circle : Icons.mic_none_rounded,
              color: _recording ? AppColors.danger : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Shortcuts(
              // 让回车直接发送（多行输入框默认会把回车当换行）
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): _SendMessageIntent(),
              },
              child: Actions(
                actions: {
                  _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                    onInvoke: (_) {
                      _onSendPressed();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _messageController,
                  enabled: !_recording,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _onSendPressed(),
                  decoration: InputDecoration(
                    hintText: '请输入你的问题…',
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      borderSide: const BorderSide(
                        color: AppColors.brand,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _messageController,
            builder: (context, value, _) {
              // 生成中：发送键变为停止键，便于中断长回答
              if (_pipelineRunning) {
                return IconButton.filled(
                  tooltip: '停止生成',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _stopGeneration,
                  icon: const Icon(Icons.stop),
                );
              }
              final canSend = value.text.trim().isNotEmpty && !_recording;
              return IconButton.filled(
                tooltip: '发送',
                onPressed: canSend ? _onSendPressed : null,
                icon: const Icon(Icons.send),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppTheme.pagePadding(width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _historyName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '检索法条',
            onPressed: _caches.isEmpty ? null : _openLaws,
            icon: Badge(
              isLabelVisible: _caches.isNotEmpty,
              label: Text('${_caches.length}'),
              child: const Icon(Icons.menu_book_outlined),
            ),
          ),
          IconButton(
            tooltip: '新建对话',
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(pad)),
          _buildProgressStrip(pad),
          _buildComposer(pad),
        ],
      ),
    );
  }
}

/// 检索法条底部抽屉
class _LawsSheet extends StatelessWidget {
  final List<String> laws;
  final List<String> details;
  final ScrollController controller;
  final TextStyle textStyle;

  const _LawsSheet({
    required this.laws,
    required this.details,
    required this.controller,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, color: AppColors.brand),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '检索到的法条（${laws.length}）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: laws.length,
            itemBuilder: (context, index) {
              return ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.article_outlined,
                    color: AppColors.textSecondary),
                title: Text(
                  laws[index],
                  style: textStyle.copyWith(fontWeight: FontWeight.w600),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    index < details.length ? details[index] : '',
                    style: textStyle.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 聊天气泡
class _Bubble extends StatelessWidget {
  final String sender;
  final String content;
  final AppConfig appConfig;
  final double maxWidth;

  const _Bubble({
    required this.sender,
    required this.content,
    required this.appConfig,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = sender == 'user';
    final fontSize = appConfig.textStyle.fontSize ?? 14;

    // 注意：ChatBubble 内部是 Container(alignment: topLeft)，一旦设置 alignment 就会
    // 撑满可用宽度；此时在外部再包 Align 不会生效（外层拿到的是满宽盒子），会导致
    // 收发消息都贴左。因此必须使用 ChatBubble 自身的 alignment 参数来左右对齐。
    return ChatBubble(
      backGroundColor:
          isUser ? AppColors.userBubble : AppColors.assistantBubble,
      clipper: ChatBubbleClipper10(
        type: isUser ? BubbleType.sendBubble : BubbleType.receiverBubble,
      ),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          content,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.4,
            color: isUser
                ? AppColors.userBubbleText
                : appConfig.textStyle.color,
          ),
        ),
      ),
    );
<<<<<<< HEAD

    // 详情面板
    Widget detail = AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: 20,
      bottom: 20,
      right: _showDetail ? 15 : -(MediaQuery.of(context).size.width),
      width: MediaQuery.of(context).size.width - 70,
      child: Stack(
        children: [
          Container(
            height: double.infinity,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Flex(
              direction: Axis.vertical,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 10,
              children: [
                const SizedBox(height: 30),
                StepProgress(
                  totalSteps: 4,
                  stepNodeSize: 20,
                  nodeTitles: ["RAG检索", "构建提示词", "分词", "推理"],
                  controller: _stepProgressController,
                  theme: const StepProgressThemeData(
                    nodeLabelAlignment: StepLabelAlignment.top,
                    stepLineSpacing: 2,
                    stepLineStyle: StepLineStyle(lineThickness: 2),
                    activeForegroundColor: Colors.lightBlueAccent,
                  ),
                ),
                const SizedBox(height: 20),
                _caches.isEmpty
                    ? const SizedBox.shrink()
                    : Expanded(
                        child: ListView.separated(
                          itemCount: _caches.length,
                          itemBuilder: (BuildContext context, int index) {
                            return TextButton(
                              onPressed: () {
                                showAlertDialog(
                                  context,
                                  _details[index],
                                  title: const Icon(Icons.details),
                                  textStyle: widget._appConfig.textStyle,
                                );
                              },
                              child: Text(
                                _caches[index],
                                style: widget._appConfig.textStyle,
                              ),
                            );
                          },
                          separatorBuilder: (BuildContext context, int index) {
                            return Divider();
                          },
                        ),
                      ),
              ],
            ),
          ),
          Positioned(
            top: 5,
            right: 10,
            child: IconButton(
              onPressed: () {
                setState(() {
                  _showDetail = false;
                });
              },
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        children: [
          Flex(
            direction: Axis.vertical,
            children: [
              Container(
                height: 60,
                child: Center(
                  child: Text(_historyName, style: widget._appConfig.textStyle),
                ),
              ),
              Divider(color: Colors.grey[100]),
              const SizedBox(height: 15),
              Expanded(
                child: ListView.separated(
                  itemBuilder: (context, index) => _Bubble(
                    appConfig: widget._appConfig,
                    sender: _history[index]["role"],
                    content: _history[index]["content"],
                  ),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 30),
                  itemCount: _history.length,
                ),
              ),
              Container(
                height: 60,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        if (!_recording) {
                          setState(() {
                            _recording = true;
                          });
                          _startRecord();
                        } else {
                          setState(() {
                            _recording = false;
                          });
                          _stopRecord();

                          final message = await _voiceToText();

                          if (message != null) {
                            _sendMessage(message);
                          }
                        }
                      },
                      icon: Icon(
                        _recording ? Icons.stop : Icons.mic,
                        color: _recording ? Colors.red : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: TextField(
                        enabled: !_recording,
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: "请输入",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      onPressed: () {
                        if (_messageController.text.isNotEmpty) {
                          _sendMessage(_messageController.text);
                          _messageController.clear();
                        } else {
                          showAlertDialog(
                            context,
                            "输入不能为空!",
                            textStyle: widget._appConfig.textStyle,
                          );
                        }
                      },
                      icon: const Icon(Icons.send, size: 25),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 10,
            right: 0,
            child: IconButton(
              onPressed: () {
                if (_stepProgressController.currentStep != -1) {
                  setState(() {
                    _showDetail = true;
                  });
                }
              },
              icon: const Icon(Icons.list, size: 30),
            ),
          ),
          Positioned(
            top: 10,
            left: 0,
            child: IconButton(
              onPressed: _toggleDrawer,
              icon: const Icon(Icons.history, size: 30),
            ),
          ),
          overlay,
          drawer,
          detail,
        ],
      ),
    );
  }

  Future<void> _startProgress() async {
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();

    setState(() {
      _caches.add("总则");
      _caches.add("网络安全支持与促进");
      _details.add(
        """第一条　为了保障网络安全，维护网络空间主权和国家安全、社会公共利益，保护公民、法人和其他组织的合法权益，促进经济社会信息化健康发展，制定本法。

      第二条　在中华人民共和国境内建设、运营、维护和使用网络，以及网络安全的监督管理，适用本法。

      第三条　网络安全工作坚持中国共产党的领导，贯彻总体国家安全观，统筹发展和安全，推进网络强国建设。

      第四条　国家坚持网络安全与信息化发展并重，遵循积极利用、科学发展、依法管理、确保安全的方针，推进网络基础设施建设和互联互通，鼓励网络技术创新和应用，支持培养网络安全人才，建立健全网络安全保障体系，提高网络安全保护能力。

      第五条　国家制定并不断完善网络安全战略，明确保障网络安全的基本要求和主要目标，提出重点领域的网络安全政策、工作任务和措施。

      第六条　国家采取措施，监测、防御、处置来源于中华人民共和国境内外的网络安全风险和威胁，保护关键信息基础设施免受攻击、侵入、干扰和破坏，依法惩治网络违法犯罪活动，维护网络空间安全和秩序。

      第七条　国家倡导诚实守信、健康文明的网络行为，推动传播社会主义核心价值观，采取措施提高全社会的网络安全意识和水平，形成全社会共同参与促进网络安全的良好环境。

      第八条　国家积极开展网络空间治理、网络技术研发和标准制定、打击网络违法犯罪等方面的国际交流与合作，推动构建和平、安全、开放、合作的网络空间，建立多边、民主、透明的网络治理体系。

      第九条　国家网信部门负责统筹协调网络安全工作和相关监督管理工作。国务院电信主管部门、公安部门和其他有关机关依照本法和有关法律、行政法规的规定，在各自职责范围内负责网络安全保护和监督管理工作。

      县级以上地方人民政府有关部门的网络安全保护和监督管理职责，按照国家有关规定确定。

      第十条　网络运营者开展经营和服务活动，必须遵守法律、行政法规，尊重社会公德，遵守商业道德，诚实信用，履行网络安全保护义务，接受政府和社会的监督，承担社会责任。

      第十一条　建设、运营网络或者通过网络提供服务，应当依照法律、行政法规的规定和国家标准的强制性要求，采取技术措施和其他必要措施，保障网络安全、稳定运行，有效应对网络安全事件，防范网络违法犯罪活动，维护网络数据的完整性、保密性和可用性。

      第十二条　网络相关行业组织按照章程，加强行业自律，制定网络安全行为规范，指导会员加强网络安全保护，提高网络安全保护水平，促进行业健康发展。

      第十三条　国家保护公民、法人和其他组织依法使用网络的权利，促进网络接入普及，提升网络服务水平，为社会提供安全、便利的网络服务，保障网络信息依法有序自由流动。

      任何个人和组织使用网络应当遵守宪法法律，遵守公共秩序，尊重社会公德，不得危害网络安全，不得利用网络从事危害国家安全、荣誉和利益，煽动颠覆国家政权、推翻社会主义制度，煽动分裂国家、破坏国家统一，宣扬恐怖主义、极端主义，宣扬民族仇恨、民族歧视，传播暴力、淫秽色情信息，编造、传播虚假信息扰乱经济秩序和社会秩序，以及侵害他人名誉、隐私、知识产权和其他合法权益等活动。

      第十四条　国家支持研究开发有利于未成年人健康成长的网络产品和服务，依法惩治利用网络从事危害未成年人身心健康的活动，为未成年人提供安全、健康的网络环境。

      第十五条　任何个人和组织有权对危害网络安全的行为向网信、电信、公安等部门举报。收到举报的部门应当及时依法作出处理；不属于本部门职责的，应当及时移送有权处理的部门。

      有关部门应当对举报人的相关信息予以保密，保护举报人的合法权益。
""",
      );
      _details.add(
        """第十六条　国家建立和完善网络安全标准体系。国务院标准化行政主管部门和国务院其他有关部门根据各自的职责，组织制定并适时修订有关网络安全管理以及网络产品、服务和运行安全的国家标准、行业标准。

      国家支持企业、研究机构、高等学校、网络相关行业组织参与网络安全国家标准、行业标准的制定。

      第十七条　国务院和省、自治区、直辖市人民政府应当统筹规划，加大投入，扶持重点网络安全技术产业和项目，支持网络安全技术的研究开发和应用，推广安全可信的网络产品和服务，保护网络技术知识产权，支持企业、研究机构和高等学校等参与国家网络安全技术创新项目。

      第十八条　国家推进网络安全社会化服务体系建设，鼓励有关企业、机构开展网络安全认证、检测和风险评估等安全服务。

      第十九条　国家鼓励开发网络数据安全保护和利用技术，促进公共数据资源开放，推动技术创新和经济社会发展。

      第二十条　国家支持人工智能基础理论研究和算法等关键技术研发，推进训练数据资源、算力等基础设施建设，完善人工智能伦理规范，加强风险监测评估和安全监管，促进人工智能应用和健康发展。

      国家支持创新网络安全管理方式，运用人工智能等新技术，提升网络安全保护水平。

      第二十一条　各级人民政府及其有关部门应当组织开展经常性的网络安全宣传教育，并指导、督促有关单位做好网络安全宣传教育工作。

      大众传播媒介应当有针对性地面向社会进行网络安全宣传教育。

      第二十二条　国家支持企业和高等学校、职业学校等教育培训机构开展网络安全相关教育与培训，采取多种方式培养网络安全人才，促进网络安全人才交流。
""",
      );
    });

    widget._addCache(LawCache(_historyName, _caches, _details));
  }
}

class _Bubble extends StatelessWidget {
  final String _sender;
  final String _content;
  final AppConfig _appConfig;

  const _Bubble({
    Key? key,
    required this._sender,
    required this._content,
    required this._appConfig,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: (_sender == "user")
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (_sender == "user")
            ? [
                ChatBubble(
                  backGroundColor: const Color(0xFF2B6BFF), // DeepSeek 品牌蓝
                  clipper: ChatBubbleClipper10(type: BubbleType.sendBubble),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.6,
                    ),
                    child: Text(
                      _content,
                      style: TextStyle(
                        color: const Color(0xFFFFFFFF),
                        fontSize: _appConfig.textStyle.fontSize,
                      ),
                    ),
                  ),
                ),
              ]
            : [
                ChatBubble(
                  backGroundColor: Colors.grey[300],
                  clipper: ChatBubbleClipper10(type: BubbleType.receiverBubble),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.55,
                    ),
                    child: Text(_content, style: _appConfig.textStyle),
                  ),
                ),
              ],
      ),
    );
=======
>>>>>>> 7417a5176b1f7f89b37c6e3094d5140f108b7e75
  }
}
