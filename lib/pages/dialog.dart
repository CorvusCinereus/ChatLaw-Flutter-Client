/**
 * @file dialog.dart
 * @brief 自定义对话框（统一样式：圆角、宽度上限、随主题字号）
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

import '../internal/design.dart';

/// 提示对话框（单按钮）。
Future<void> showAlertDialog(
  BuildContext context,
  String content, {
  Widget? title,
  TextStyle? textStyle,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: title ??
            const Icon(Icons.info_outline, color: AppColors.brand, size: 28),
        content: _DialogContent(content: content, textStyle: textStyle),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
}

/// 询问对话框（取消 / 确定）。
///
/// [destructive] 为 true 时确认按钮使用危险色（用于删除等不可逆操作）。
Future<bool> showAskDialog(
  BuildContext context,
  String content, {
  String confirmText = '确定',
  String cancelText = '取消',
  bool barrierDismissible = false,
  bool destructive = false,
  TextStyle? textStyle,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Icon(
              destructive ? Icons.warning_amber_rounded : Icons.help_outline,
              color: destructive ? AppColors.danger : AppColors.brand,
              size: 28,
            ),
            content: _DialogContent(content: content, textStyle: textStyle),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancelText),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                    : null,
                child: Text(confirmText),
              ),
            ],
          );
        },
      ) ??
      false; // 点击外部/返回键关闭时按 false 处理
}

/// 统一的弹窗内容：限宽 + 可滚动，避免长法条撑成细高条。
class _DialogContent extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;

  const _DialogContent({required this.content, this.textStyle});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
      child: SingleChildScrollView(
        child: Text(content, style: textStyle),
      ),
    );
  }
}
