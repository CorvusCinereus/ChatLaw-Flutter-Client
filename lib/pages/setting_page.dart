/**
 * @file setting_page.dart
 * @brief 设置页面（管理服务器配置）
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

import '../internal/config.dart';
import '../internal/design.dart';
import 'dialog.dart';
import 'page_index.dart';
import 'server_tile.dart';

class SettingPage extends StatefulWidget {
  final AppConfig appConfig;
  final String? serverName;
  final Function(String name, String address) addServer;
  final Function(String name) removeServer;
  final Function(PageIndex page, {String? serverName}) setPage;

  /// 返回来源页；未注入时回退到开始页。
  final VoidCallback? onBack;

  const SettingPage({
    super.key,
    required this.appConfig,
    required this.serverName,
    required this.addServer,
    required this.removeServer,
    required this.setPage,
    this.onBack,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  void _goBack() {
    final back = widget.onBack;
    if (back != null) {
      back();
    } else {
      widget.setPage(PageIndex.start);
    }
  }

  Future<void> _confirmRemove(String name) async {
    final ok = await showAskDialog(
      context,
      '确定删除服务器「$name」吗？',
      destructive: true,
      confirmText: '删除',
      textStyle: widget.appConfig.textStyle,
    );
    if (!ok) return;
    widget.removeServer(name);
    setState(() {});
  }

  /// 服务器管理区（开始页的同一套条目组件）
  Widget _buildServerManager({required double pad}) {
    final servers = widget.appConfig.serverConfigs;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: AppSpacing.lg),
      children: [
        Text('服务器', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '管理对话所要连接的服务器 IP（端口由服务端固定）。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (servers.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                '还没有配置服务器，点击下方按钮添加。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...servers.map(
            (server) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ServerTile(
                server: server,
                onTap: () => widget.setPage(
                  PageIndex.chat,
                  serverName: server.name,
                ),
                onEdit: () =>
                    widget.setPage(PageIndex.server, serverName: server.name),
                onRemove: () => _confirmRemove(server.name),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: () => widget.setPage(PageIndex.server),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加服务器'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Divider(color: AppColors.divider),
        const SizedBox(height: AppSpacing.sm),
        ListTile(
          onTap: () => widget.setPage(PageIndex.start),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          leading: const Icon(Icons.home_outlined),
          title: const Text('回到主页'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ],
    );
  }

  /// 宽屏侧栏的分区条目
  Widget _railItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.brand : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.brand : AppColors.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
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
            final wide = constraints.maxWidth >= AppBreakpoints.compact;

            if (!wide) {
              return _buildServerManager(pad: pad);
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 208,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    children: [
                      _railItem(
                        icon: Icons.dns_outlined,
                        label: '服务器',
                        selected: true,
                        onTap: () {},
                      ),
                      _railItem(
                        icon: Icons.home_outlined,
                        label: '回到主页',
                        selected: false,
                        onTap: () => widget.setPage(PageIndex.start),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildServerManager(pad: pad)),
              ],
            );
          },
        ),
      ),
    );
  }
}
