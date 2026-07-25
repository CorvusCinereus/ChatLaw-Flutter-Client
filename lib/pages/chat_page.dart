/**
 * @file chat_page.dart
 * @brief 聊天页面
 * @author CorvusCinereus
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:chatlaw/internal/config.dart';
import "package:flutter_chat_bubble/chat_bubble.dart";
import 'package:chatlaw/pages/dialog.dart';
import 'package:chatlaw/pages/page_index.dart';

class ChatPage extends StatefulWidget {
  final AppConfig _appConfig;
  final String _serverName;
  final Function(PageIndex page, {String? serverName}) _setPage;
  final Function(Map<String, dynamic> history) _addHistory;

  const ChatPage({
    super.key,
    required this._appConfig,
    required this._serverName,
    required this._setPage,
    required this._addHistory,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  int _serverIndex = -1;
  String _historyName = "未命名对话";
  List<Map<String, dynamic>> _history = [];
  TextEditingController _messageController = TextEditingController();

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
      showAlertDialog(context, "服务器不存在");
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
    setState(() {
      _isDrawerOpen = !_isDrawerOpen;
      if (_isDrawerOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
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
        title: Text(
          title,
          style: const TextStyle(color: Colors.black),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          _closeDrawer();
          setState(() {
            _historyName = item["name"] ?? "未命名对话";
            _history = (item["history"] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
          });
        },
      );
    }).toList();
  }

  void _sendMessage(String message) {
    setState(() {
      if (_historyName == "未命名对话") {
        _historyName = message.length < 7 ? message : message.substring(0, 6);
      }
      _history.add({"role": "user", "content": message});
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
                    child: Column(
                      children: [
                        Text('历史对话', style: widget._appConfig.textStyle),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _historyName = "未命名对话";
                              _history = [];
                            });
                            _closeDrawer();
                          },
                          child: Text(
                            "新对话",
                            style: widget._appConfig.textStyle,
                          ),
                        ),
                      ],
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
                          showAlertDialog(context, "输入不能为空!");
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
              onPressed: () {},
              icon: const Icon(Icons.list, size: 30),
            ),
          ),
          Positioned(
            top: 10,
            left: 0,
            child: IconButton(
              onPressed: _toggleDrawer,
              icon: Icon(Icons.history, size: 30),
            ),
          ),
          overlay,
          drawer,
        ],
      ),
    );
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
