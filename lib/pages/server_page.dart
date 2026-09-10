/**
 * @file server_page.dart
 * @brief 服务器配置页面（新增 / 编辑）
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

import '../internal/config.dart';
import '../internal/design.dart';
import 'dialog.dart';
import 'page_index.dart';

class ServerPage extends StatefulWidget {
  final AppConfig config;
  final String? serverName;

  /// true 表示从设置页进入（可删除、名称锁定）；false 表示新增。
  final bool subPage;

  final Function(String name, String address) addServer;
  final Function(String name) removeServer;
  final Function(PageIndex page, {String? serverName}) setPage;

  /// 返回来源页；未注入时回退到开始页。
  final VoidCallback? onBack;

  const ServerPage({
    super.key,
    required this.config,
    this.serverName,
    required this.subPage,
    required this.addServer,
    required this.removeServer,
    required this.setPage,
    this.onBack,
  });

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 仅在初始化时预填一次（此前在 build 中每次重建都覆盖，会吞掉用户输入）。
    final name = widget.serverName;
    if (name != null) {
      final index = widget.config.serverConfigs.indexWhere(
        (element) => element.name == name,
      );
      if (index != -1) {
        _nameController.text = widget.config.serverConfigs[index].name;
        _addressController.text = widget.config.serverConfigs[index].address;
      } else {
        _nameController.text = name;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _goBack() {
    final back = widget.onBack;
    if (back != null) {
      back();
    } else {
      widget.setPage(PageIndex.start);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    final address = _addressController.text.trim();

    final exists = widget.config.serverConfigs.any((e) => e.name == name);
    if (exists && !widget.subPage) {
      showAlertDialog(
        context,
        '服务器「$name」已存在，请更换名称。',
        textStyle: widget.config.textStyle,
      );
      return;
    }

    widget.addServer(name, address);
    _goBack();
  }

  Future<void> _delete() async {
    final name = widget.serverName;
    if (name == null) return;
    final ok = await showAskDialog(
      context,
      '确定删除服务器「$name」吗？',
      destructive: true,
      confirmText: '删除',
      textStyle: widget.config.textStyle,
    );
    if (!ok) return;
    widget.removeServer(name);
    _goBack();
  }

  String? _validateName(String? value) {
    if ((value ?? '').trim().isEmpty) return '请填写服务器名称';
    return null;
  }

  String? _validateAddress(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '请填写服务器地址';
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      return '请填写完整地址（以 http:// 或 https:// 开头）';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.config.textStyle;
    final isEditing = widget.subPage;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑服务器' : '添加服务器'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = AppTheme.pagePadding(constraints.maxWidth);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.formMaxWidth,
                ),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: pad,
                      vertical: AppSpacing.xl,
                    ),
                    children: [
                      TextFormField(
                        controller: _nameController,
                        readOnly: isEditing,
                        textInputAction: TextInputAction.next,
                        style: textStyle,
                        decoration: InputDecoration(
                          labelText: '服务器名称',
                          hintText: '例如：默认',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          helperText: isEditing ? '编辑时不可修改名称' : null,
                        ),
                        validator: _validateName,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: _addressController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        style: textStyle,
                        onFieldSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: '例如：http://localhost:8080',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                        validator: _validateAddress,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
                      if (isEditing) ...[
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton.icon(
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.danger),
                          label: const Text(
                            '删除该服务器',
                            style: TextStyle(color: AppColors.danger),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
