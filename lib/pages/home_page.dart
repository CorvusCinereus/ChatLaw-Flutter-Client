/**
 * @file home_page.dart
 * @brief HomePage(负责切换页面)
 * @author CorvusCinereus
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:chatlaw/pages/start_page.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:chatlaw/internal/config.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppConfig? _config;
  Widget? _body;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child:
            _body ??
            const Center(child: CircularProgressIndicator()), // 等待配置加载时显示加载动画
      ),
    );
  }

  /// @brief 切换页面
  /// @param page 页面索引
  /// @param serverName 服务器名称(在切换到聊天、服务器配置和设置页面时需要)
  /// @return 无
  void _setPage(PageIndex page, {String? serverName}) {
    switch (page) {
      case PageIndex.start:
        setState(() {
          _body = StartPage(config: _config!, setPage: _setPage);
        });
        break;
      case PageIndex.chat:
        break;
      case PageIndex.server:
        break;
      case PageIndex.setting:
        break;
    }
  }

  /// @brief 加载应用配置
  void _loadConfig() async {
    final path = await getApplicationDocumentsDirectory();
    final dir = Directory("${path.path}/ChatLaw");
    if (await dir.exists()) {
      final file = File('${dir.path}/config.json');
      if (await file.exists()) {
        final json = await file.readAsString();
        _config = AppConfig.fromJson(jsonDecode(json));
      } else {
        _config = AppConfig.defaultConfig();
      }
    } else {
      await dir.create(recursive: true);
      _config = AppConfig.defaultConfig();
    }
    _setPage(PageIndex.start);
  }
}
