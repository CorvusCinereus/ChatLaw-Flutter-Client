/**
 * @file main.dart
 * @brief 应用入口
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatLaw',
      home: HomePage(),
    );
  }
}