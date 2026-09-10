/**
 * @file chat_page.dart
 * @brief 聊天页面：提问 → RAG 检索 → 构建提示词 → 分词 → 虚拟回答
 * @author CorvusCinereus
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../internal/config.dart';
import '../internal/design.dart';
import '../services/chat_pipeline.dart';
import '../services/mock_answer.dart';
import 'dialog.dart';
import 'page_index.dart';

/// 流水线步骤（与 _step 的 0..4 对应）
const List<String> _kSteps = ['RAG检索', '构建提示词', '分词', '推理'];

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
    setState(() => _step = 0);

    final pipeline = ChatPipeline.debugOverride ?? ChatPipeline();
    List<RagDoc> docs = [];

    try {
      // 步骤 1：真实 RAG 检索
      docs = await pipeline.runRag(question);
      if (!mounted) return;
      setState(() {
        _caches = docs.map((d) => d.title).toList();
        _details = docs.map((d) => d.content).toList();
        _step = 1;
      });

      // 步骤 2：构建 prompt
      await pipeline.runBuild();
      if (!mounted) return;
      setState(() => _step = 2);

      // 步骤 3：分词
      await pipeline.runTokenize();
      if (!mounted) return;
      setState(() => _step = 3);

      // 步骤 4：推理（服务器未接入，用虚拟文本）
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _step = 4;
        _history.add({
          'role': 'assistant',
          'content': buildVirtualAnswer(question, docs),
        });
      });
      _scrollToBottomSoon();
      widget.addHistory({'name': _historyName, 'history': _history});
      if (_caches.isNotEmpty) {
        widget.addCache(LawCache(_historyName, _caches, _details));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history.add({
          'role': 'assistant',
          'content': '⚠️ 流水线执行失败：$e',
        });
      });
      _scrollToBottomSoon();
      widget.addHistory({'name': _historyName, 'history': _history});
    } finally {
      if (mounted) setState(() => _pipelineRunning = false);
    }
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
              final canSend = value.text.trim().isNotEmpty &&
                  !_pipelineRunning &&
                  !_recording;
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
  }
}
