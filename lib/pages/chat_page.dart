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

class ChatPage extends StatefulWidget {
  final AppConfig _appConfig;
  final String _serverName;
  final Function(PageIndex page, {String? serverName}) _setPage;

  const ChatPage({
    super.key,
    required this._appConfig,
    required this._serverName,
    required this._setPage,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  int _serverIndex = -1;
  List<Map<String, dynamic>> _history = [];

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
        // _history = widget._appConfig.history[_serverIndex]["history"];
        _history = [
          {"role": "user", "content": "你好"},
          {"role": "assistant", "content": "你好"},
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        children: [
          Flex(
            direction: Axis.vertical,
            children: [
              Container(height: 60),
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
                      onPressed: () {},
                      icon: const Icon(Icons.send, size: 30),
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
              onPressed: () {},
              icon: Icon(Icons.history, size: 30),
            ),
          ),
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
                        color: const Color(0xFFFFFFFF), // 纯白文字
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
