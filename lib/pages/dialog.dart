/**
 * @file dialog.dart
 * @brief 自定义对话框
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

Future<void> showAlertDialog(
  BuildContext context,
  String content, {
  Widget? title,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: title ?? const Icon(Icons.warning),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            child: const Text("确定"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

Future<bool> showAskDialog(
  BuildContext context,
  String content, {
  String confirmText = '确定',
  String cancelText = '取消',
  bool barrierDismissible = false,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Icon(Icons.help),
            content: SingleChildScrollView(child: Text(content)),
            actions: [
              TextButton(
                child: Text(cancelText),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: Text(confirmText),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      ) ??
      false; // 若用户点击外部关闭（且 barrierDismissible 为 true）或返回 null，默认返回 false
}

