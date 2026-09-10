/**
 * @file main.dart
 * @brief 应用入口
 * @author CorvusCinereus
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serious_python/serious_python.dart';
import 'package:serious_python_android/serious_python_android.dart';

import 'internal/app_state.dart';
import 'internal/config.dart';
import 'internal/design.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Android：先注册 serious_python 的 Android 平台实现（prepareApp/run 都依赖它；
  // 默认 MethodChannelSeriousPython 未实现 prepareApp，不注册会在首次解包处
  // 直接抛 UnimplementedError）。随后后台启动内嵌 Python（main.py HTTP 服务）。
  // 首次启动会解包 app.zip（python 模块 + resources/，数百 MB），耗时较长，
  // 故不阻塞 runApp；HomePage 的 BootPage 会等待 /health 就绪后进入开始页。
  if (Platform.isAndroid) {
    SeriousPythonAndroid.registerWith();
    unawaited(
      SeriousPython.run().then((_) {
        debugPrint('[chatlaw] SeriousPython 已启动');
      }).catchError((Object e, StackTrace st) {
        debugPrint('[chatlaw] SeriousPython 启动失败: $e');
        debugPrint('$st');
        return null;
      }),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 主题随用户配置（字号/颜色/字体族）变化而重建；配置未加载时用默认基准。
    return ValueListenableBuilder<AppConfig?>(
      valueListenable: configNotifier,
      builder: (context, config, _) {
        return MaterialApp(
          title: 'ChatLaw',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(config),
          home: const HomePage(),
        );
      },
    );
  }
}
