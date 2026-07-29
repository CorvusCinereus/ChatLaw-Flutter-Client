/**
 * @file chat_page.dart
 * @brief 聊天页面
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';
import 'package:chatlaw/internal/config.dart';
import "package:flutter_chat_bubble/chat_bubble.dart";
import 'package:chatlaw/pages/dialog.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:step_progress/step_progress.dart';

class ChatPage extends StatefulWidget {
  final AppConfig _appConfig;
  final String _serverName;
  final Function(PageIndex page, {String? serverName}) _setPage;
  final Function(Map<String, dynamic> history) _addHistory;
  final Function(String name) _removeHistory;
  final Function(LawCache cache) _addCache;
  final Function(String oldName, String newName) _renameCache;

  const ChatPage({
    super.key,
    required this._appConfig,
    required this._serverName,
    required this._setPage,
    required this._addHistory,
    required this._removeHistory,
    required this._addCache,
    required this._renameCache,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  int _serverIndex = -1;
  String _historyName = "未命名对话";
  bool _showDetail = false;
  List<Map<String, dynamic>> _history = [];
  List<String> _caches = [];
  final TextEditingController _messageController = TextEditingController();
  final StepProgressController _stepProgressController = StepProgressController(
    totalSteps: 4,
  );

  bool _isDrawerOpen = false;
  late AnimationController _animationController;
  List<Widget>? _drawerItems;

  @override
  void initState() {
    super.initState();
    _serverIndex = widget._appConfig.serverConfigs.indexWhere(
      (element) => element.name == widget._serverName,
    );
    if (_serverIndex == -1) {
      showAlertDialog(
        context,
        "服务器不存在",
        textStyle: widget._appConfig.textStyle,
      );
      widget._setPage(PageIndex.start);
    } else {
      setState(() {
        _history = [];
      });
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// @brief 切换抽屉状态
  void _toggleDrawer() {
    if (!_showDetail) {
      setState(() {
        _isDrawerOpen = !_isDrawerOpen;
        if (_isDrawerOpen) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }
      });
    }
  }

  /// @brief 关闭抽屉
  void _closeDrawer() {
    if (_isDrawerOpen) {
      setState(() {
        _isDrawerOpen = false;
        _animationController.reverse();
      });
    }
  }

  List<Widget> _buildDrawerItems() {
    if (_drawerItems != null) {
      return _drawerItems!;
    }

    final historyList = widget._appConfig.history;
    if (historyList.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '暂无历史记录',
            style: TextStyle(
              color: Colors.grey,
              fontSize: widget._appConfig.textStyle.fontSize,
            ),
          ),
        ),
      ];
    }

    return historyList.map<Widget>((item) {
      final title = item["name"] ?? "未命名对话";
      return ListTile(
        leading: const Icon(Icons.chat, color: Colors.black),
        title: Row(
          spacing: 5,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.black),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton(
              child: IconButton(
                onPressed: null,
                icon: const Icon(Icons.more_vert, color: Colors.black),
              ),
              itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                PopupMenuItem(
                  value: 1,
                  child: ListTile(
                    leading: const Icon(Icons.edit),
                    title: Text("重命名对话", style: widget._appConfig.textStyle),
                  ),
                ),
                PopupMenuItem(
                  value: 2,
                  child: ListTile(
                    leading: const Icon(Icons.delete),
                    title: Text("删除对话", style: widget._appConfig.textStyle),
                  ),
                ),
              ],
              onSelected: (value) async {
                if (value == 1) {
                  final TextEditingController newNameController =
                      TextEditingController();

                  final String? newName = await showDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Icon(Icons.edit),
                      content: TextField(
                        controller: newNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: "请输入新对话名称",
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (value) {
                          Navigator.of(context).pop(value);
                        },
                      ),
                      actions: [
                        // 取消按钮
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // 返回 null
                          },
                          child: const Text('取消'),
                        ),
                        // 确认按钮
                        ElevatedButton(
                          onPressed: () {
                            // 点击确认时，将输入框的内容作为结果返回
                            Navigator.of(context).pop(newNameController.text);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                  if (newName != null) {
                    setState(() {
                      widget._renameCache(_historyName, newName);
                      _historyName = newName;
                      item["name"] = newName;
                      widget._addHistory(item);
                    });
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    newNameController.dispose();
                  });
                } else if (value == 2 &&
                    await showAskDialog(context, "是否删除该对话?")) {
                  setState(() {
                    _history = [];
                    _historyName = "未命名对话";
                    widget._removeHistory(title);
                    _closeDrawer();
                  });
                }
              },
            ),
          ],
        ),
        onTap: () {
          _closeDrawer();
          setState(() {
            _historyName = item["name"] ?? "未命名对话";
            _history = (item["history"] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();

            // 加载缓存
            final index = widget._appConfig.lawCaches.indexWhere(
              (element) => element.name == _historyName,
            );
            if (index != -1) {
              _caches = widget._appConfig.lawCaches[index].laws;
              if (_caches.isNotEmpty) {
                _stepProgressController.setCurrentStep(3);
              }
            }
          });
        },
      );
    }).toList();
  }

  void _sendMessage(String message) {
    _stepProgressController.setCurrentStep(-1); // 重置进度条
    setState(() {
      if (_historyName == "未命名对话") {
        _historyName = message.length < 7 ? message : message.substring(0, 6);
      }
      _history.add({"role": "user", "content": message});
      _showDetail = true;
      _startProgress();
    });
    widget._addHistory({"name": _historyName, "history": _history});
  }

  @override
  Widget build(BuildContext context) {
    // 遮罩层（点击关闭）
    Widget overlay = Positioned.fill(
      child: FadeTransition(
        opacity: _animationController,
        child: IgnorePointer(
          ignoring: !_isDrawerOpen, // 关闭时忽略点击，避免误触
          child: GestureDetector(
            onTap: _closeDrawer,
            child: Container(color: Colors.black54),
          ),
        ),
      ),
    );

    // 抽屉面板
    Widget drawer = AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      left: _isDrawerOpen ? 0 : -MediaQuery.of(context).size.width * 0.75,
      width: MediaQuery.of(context).size.width * 0.75,
      child: FadeTransition(
        opacity: _animationController,
        child: IgnorePointer(
          ignoring: !_isDrawerOpen,
          child: Material(
            color: const Color.fromARGB(255, 234, 232, 232),
            elevation: 8.0,
            child: SafeArea(
              child: Column(
                children: [
                  DrawerHeader(
                    child: SingleChildScrollView(
                      child: Column(
                        spacing: 10,
                        children: [
                          Text('历史对话', style: widget._appConfig.textStyle),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _historyName = "未命名对话";
                                _history = [];
                                _caches = [];
                                _stepProgressController.setCurrentStep(-1);
                              });
                              _closeDrawer();
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              "新对话",
                              style: widget._appConfig.textStyle,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              widget._setPage(
                                PageIndex.setting,
                                serverName: widget._serverName,
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.settings, color: Colors.black),
                                const SizedBox(width: 5),
                                Text("设置", style: widget._appConfig.textStyle),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _buildDrawerItems(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

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
                  nodeTitles: ["RAG检索", "构建提示词", "分词", "推理"],
                  controller: _stepProgressController,
                  theme: const StepProgressThemeData(
                    nodeLabelAlignment: StepLabelAlignment.top,
                    stepLineSpacing: 2,
                    stepLineStyle: StepLineStyle(lineThickness: 2),
                    activeForegroundColor: Colors.lightBlueAccent,
                  ),
                ),
                // ListView.separated()
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
                    Expanded(
                      child: TextField(
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

    _caches.add("法律条文1");
    _caches.add("法律条文2");

    widget._addCache(LawCache(_historyName, _caches));
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
  }
}
