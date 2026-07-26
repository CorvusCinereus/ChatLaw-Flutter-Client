import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:flutter/material.dart';

/**
 * @file setting_page.dart
 * @brief 设置页面
 * @author CorvusCinereus
 */

class SettingPage extends StatefulWidget {
  final AppConfig _appConfig;
  final String? _serverName;
  final Function(PageIndex page, {String? serverName}) _setPage;

  const SettingPage({
    super.key,
    required this._appConfig,
    required this._serverName,
    required this._setPage,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Flex(
            direction: Axis.horizontal,
            children: [
              Expanded(flex: 1, child: Container()),
              VerticalDivider(),
              Expanded(flex: 3, child: Container()),
            ],
          ),
        ),
        Positioned(
          top: 5,
          left: 20,
          child: IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              widget._setPage(PageIndex.chat, serverName: widget._serverName);
            },
          ),
        ),
      ],
    );
  }
}
