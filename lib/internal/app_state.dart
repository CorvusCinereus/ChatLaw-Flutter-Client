/**
 * @file app_state.dart
 * @brief 全局应用状态（配置通知器）
 * @author CorvusCinereus
 *
 * HomePage 加载/保存配置后写入，MaterialApp 据此重建主题（字号/颜色/字体族）。
 */

import 'package:flutter/foundation.dart';

import 'config.dart';

/// 当前应用配置；null 表示尚未加载完成（使用默认主题基准）。
final ValueNotifier<AppConfig?> configNotifier = ValueNotifier<AppConfig?>(null);
