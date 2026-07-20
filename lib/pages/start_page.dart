/**
 * @file start_page.dart
 * @brief 开始页面, 负责配置管理
 * @author CorvusCinereus
 */

import 'package:chatlaw/pages/page_index.dart';
import 'package:flutter/material.dart';
import 'package:chatlaw/internal/config.dart';

class StartPage extends StatefulWidget {
  final AppConfig config;
  final Function(PageIndex page, {String? serverName}) setPage;

  const StartPage({super.key, required this.config, required this.setPage});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 20,
                children: [
                  // 已有的服务器配置按钮
                  ...widget.config.serverConfigs.map(
                    (config) => ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: () {
                        widget.setPage(PageIndex.chat, serverName: config.name);
                      },
                      child: Text(config.name, style: widget.config.textStyle),
                    ),
                  ),
                  // 添加按钮
                  IconButton(
                    onPressed: () {
                      widget.setPage(PageIndex.server);
                    },
                    icon: Icon(
                      Icons.add,
                      size: 40,
                      color: widget.config.textStyle.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
