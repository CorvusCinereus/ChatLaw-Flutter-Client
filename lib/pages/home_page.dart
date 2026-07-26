/**
 * @file home_page.dart
 * @brief HomePage(负责切换页面)
 * @author CorvusCinereus
 */

import 'dart:convert';

import 'package:chatlaw/pages/dialog.dart';
import 'package:chatlaw/pages/setting_page.dart';
import 'package:flutter/material.dart';
import 'package:chatlaw/pages/start_page.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/pages/server_page.dart';
import 'package:chatlaw/pages/chat_page.dart';
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
        setState(() {
          _body = ChatPage(
            appConfig: _config!,
            serverName: serverName!,
            setPage: _setPage,
            addHistory: _addHistory,
            removeHistory: _removeHistory,
          );
        });
        break;
      case PageIndex.server:
        setState(() {
          _body = ServerPage(
            config: _config!,
            serverName: serverName,
            addServer: _addServer,
            setPage: _setPage,
          );
        });
        break;
      case PageIndex.setting:
        setState(() {
          _body = SettingPage(
            appConfig: _config!,
            serverName: serverName,
            setPage: _setPage,
          );
        });
        break;
    }
  }

  /// @brief 加载应用配置
  void _loadConfig() async {
    try {
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
    } catch (e) {
      _config = AppConfig.defaultConfig();
      showAlertDialog(context, "配置文件损坏，请重新配置服务器\n$e");
    }
    _setPage(PageIndex.start);
  }

  /// @brief 添加服务器配置
  /// @param name 服务器名称
  /// @param address 服务器地址
  void _addServer(String name, String address) {
    if (name.isNotEmpty && address.isNotEmpty) {
      _config!.serverConfigs.add(ServerConfig(name, address));
      _saveConfig();
    } else {
      showAlertDialog(context, "请完整填写配置信息", title: Icon(Icons.error));
    }
  }

  /// @brief 移除服务器配置
  /// @param name 服务器名称
  void _removeServer(String name) {
    _config!.serverConfigs.removeWhere((element) => element.name == name);
    _saveConfig();
  }

  /// @brief 添加历史对话
  /// @param history 对话记录
  void _addHistory(Map<String, dynamic> history) {
    _config!.history.removeWhere(
      (element) => element["name"] == history["name"],
    );
    _config!.history.add(history);
    _saveConfig();
  }

  /// @brief 移除历史对话
  /// @param name 对话名称
  void _removeHistory(String name) {
    _config!.history.removeWhere((element) => element["name"] == name);
    _saveConfig();
  }

  /// @brief 保存应用配置
  void _saveConfig() async {
    final path = await getApplicationDocumentsDirectory();
    final dir = Directory("${path.path}/ChatLaw");
    if (await dir.exists()) {
      final file = File('${dir.path}/config.json');
      await file.writeAsString(jsonEncode(_config!.toJson()));
    } else {
      await dir.create(recursive: true);
      final file = File('${dir.path}/config.json');
      await file.writeAsString(jsonEncode(_config!.toJson()));
    }
  }
}
