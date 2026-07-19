/**
 * @file server_page.dart
 * @brief 服务器配置页面
 * @author CorvusCinereus
 */
import 'package:chatlaw/pages/dialog.dart';
import 'package:chatlaw/internal/config.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:flutter/material.dart';

class ServerPage extends StatefulWidget {
  final AppConfig config;
  final String? serverName;
  final Function(String name, String address) addServer;
  final Function(PageIndex page, {String? serverName}) setPage;

  const ServerPage({
    super.key,
    required this.config,
    this.serverName,
    required this.addServer,
    required this.setPage,
  });

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  int index = -1;

  @override
  void initState() {
    super.initState();
    if (widget.serverName != null) {
      index = widget.config.serverConfigs.indexWhere(
        (element) => element.name == widget.serverName,
      );
      if (index == -1) {
        showAlertDialog(context, "找不到服务器${widget.serverName}");
        widget.setPage(PageIndex.start);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _nameController.text = widget.serverName ?? '';
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Flex(
          direction: Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 20,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('服务器名称:', style: widget.config.textStyle),
                  const SizedBox(width: 20),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: widget.config.textStyle,
                      decoration: const InputDecoration(hintText: '请输入服务器名称'),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('服务器地址:', style: widget.config.textStyle),
                  const SizedBox(width: 20),
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      style: widget.config.textStyle,
                      decoration: const InputDecoration(hintText: '请输入服务器地址'),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () {
                        widget.addServer(
                          _nameController.text,
                          _addressController.text,
                        );
                        widget.setPage(PageIndex.start);
                      },
                      child: Text('保存', style: widget.config.textStyle),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () {
                        widget.setPage(PageIndex.start);
                      },
                      child: Text('取消', style: widget.config.textStyle),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
