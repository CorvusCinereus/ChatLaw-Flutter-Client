/**
 * @file setting_page.dart
 * @brief 设置页面
 * @author CorvusCinereus
 */

import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:chatlaw/pages/server_page.dart';
import 'package:flutter/material.dart';

class SettingPage extends StatefulWidget {
  final AppConfig _appConfig;
  final String? _serverName;
  final Function(String name, String address) _addServer;
  final Function(String name) _removeServer;
  final Function(PageIndex page, {String? serverName}) _setPage;

  const SettingPage({
    super.key,
    required this._appConfig,
    required this._serverName,
    required this._addServer,
    required this._removeServer,
    required this._setPage,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int _position = 0;
  Widget _subPage = Container();

  @override
  Widget build(BuildContext context) {
    if (_position == 0) {
      _subPage = ServerPage(
        config: widget._appConfig,
        subPage: true,
        addServer: widget._addServer,
        removeServer: widget._removeServer,
        setPage: widget._setPage,
        serverName: widget._serverName,
      );
    }

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Flex(
            direction: Axis.horizontal,
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  child: Flex(
                    direction: Axis.vertical,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 10,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        decoration: (_position == 0)
                            ? BoxDecoration(
                                border: Border.all(color: Colors.black),
                                borderRadius: BorderRadius.circular(20),
                              )
                            : null,
                        child: TextButton(
                          onPressed: () {
                            _position = 0;
                            setState(() {
                              _subPage = ServerPage(
                                config: widget._appConfig,
                                subPage: true,
                                addServer: widget._addServer,
                                removeServer: widget._removeServer,
                                setPage: widget._setPage,
                                serverName: widget._serverName,
                              );
                            });
                          },
                          child: Text(
                            "服务器",
                            style: widget._appConfig.textStyle,
                          ),
                        ),
                      ),
                      Divider(),
                      TextButton(
                        onPressed: () {
                          widget._setPage(PageIndex.start);
                        },
                        child: Text("回到主页", style: widget._appConfig.textStyle),
                      ),
                    ],
                  ),
                ),
              ),
              VerticalDivider(),
              Expanded(flex: 3, child: _subPage),
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

class _ServerSubPage extends StatefulWidget {
  final AppConfig _appConfig;

  const _ServerSubPage({required this._appConfig});

  @override
  State<_ServerSubPage> createState() => _ServerSubPageState();
}

class _ServerSubPageState extends State<_ServerSubPage> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
