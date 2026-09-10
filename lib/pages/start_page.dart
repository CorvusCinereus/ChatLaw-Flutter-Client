/**
 * @file start_page.dart
 * @brief 开始页面：选择服务器进入对话，或管理服务器配置
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

import '../internal/config.dart';
import '../internal/design.dart';
import 'dialog.dart';
import 'page_index.dart';
import 'server_tile.dart';

class StartPage extends StatefulWidget {
  final AppConfig config;
  final Function(PageIndex page, {String? serverName}) setPage;

  /// 可选：在开始页直接新增/删除服务器（由 HomePage 注入）。
  final Function(String name, String address)? addServer;
  final Function(String name)? removeServer;

  const StartPage({
    super.key,
    required this.config,
    required this.setPage,
    this.addServer,
    this.removeServer,
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  /// 新增/编辑服务器（编辑时名称栏预填并锁定为原名称）。
  Future<void> _openServerEditor({String? name}) async {
    widget.setPage(PageIndex.server, serverName: name);
  }

  Future<void> _confirmRemove(String name) async {
    final ok = await showAskDialog(
      context,
      '确定删除服务器「$name」吗？',
      destructive: true,
      confirmText: '删除',
      textStyle: widget.config.textStyle,
    );
    if (!ok) return;
    final remove = widget.removeServer;
    if (remove != null) {
      remove(name);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.config.serverConfigs;
    final textStyle = widget.config.textStyle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ChatLaw'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => widget.setPage(PageIndex.setting),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = AppTheme.pagePadding(constraints.maxWidth);
            // 内容少时垂直居中，内容多时滚动，避免大屏下方大片留白。
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSizes.formMaxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: pad,
                        vertical: AppSpacing.xl,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('选择服务器配置', style: textStyle),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '模型推理结果将由配置的服务器提供。',
                            style: textStyle.copyWith(
                              fontSize: (textStyle.fontSize ?? 14) - 1,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          if (servers.isEmpty)
                            _EmptyServers(
                              textStyle: textStyle,
                              onAdd: () => _openServerEditor(),
                            )
                          else
                            ...servers.map(
                              (server) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: ServerTile(
                                  server: server,
                                  onTap: () => widget.setPage(
                                    PageIndex.chat,
                                    serverName: server.name,
                                  ),
                                  onEdit: () =>
                                      _openServerEditor(name: server.name),
                                  onRemove: () => _confirmRemove(server.name),
                                ),
                              ),
                            ),

                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.icon(
                            onPressed: () => _openServerEditor(),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('添加服务器'),
                          ),
                        ],
                      ),
                    ),
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

/// 无服务器时的空状态
class _EmptyServers extends StatelessWidget {
  final TextStyle textStyle;
  final VoidCallback onAdd;

  const _EmptyServers({required this.textStyle, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          children: [
            const Icon(Icons.dns_outlined, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text('还没有配置服务器', style: textStyle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '添加一个服务器后即可开始咨询。',
              style: textStyle.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
