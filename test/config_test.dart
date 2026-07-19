import 'package:chatlaw/internal/config.dart';
import 'package:flutter/material.dart';
import 'package:test/test.dart';

void main() {
  test('测试配置Json格式转换', () {
    final config = AppConfig.defaultConfig();
    final json = config.toJson();
    final config2 = AppConfig.fromJson(json);
    assert(config.textStyle == config2.textStyle);
    assert(config.textStyle.color == Colors.black);
    assert(config.serverConfigs.length == config2.serverConfigs.length);
  });
}
