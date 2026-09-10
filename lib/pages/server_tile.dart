/**
 * @file server_tile.dart
 * @brief 服务器条目（开始页与设置页复用）
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

import '../internal/config.dart';
import '../internal/design.dart';

class ServerTile extends StatelessWidget {
  final ServerConfig server;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  /// 是否显示右侧「更多」菜单（编辑/删除）。
  final bool showMenu;

  const ServerTile({
    super.key,
    required this.server,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
    this.showMenu = true,
  });

  @override
  Widget build(BuildContext context) {
    final initial = server.name.isEmpty ? '?' : server.name.substring(0, 1);

    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.brandSoft,
          foregroundColor: AppColors.brand,
          child: Text(
            initial,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        title: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(server.address, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: showMenu
            ? PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'remove') onRemove();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('编辑'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: AppColors.danger),
                      title: Text('删除',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      ),
    );
  }
}
