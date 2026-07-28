import 'package:chatlaw/internal/config.dart';
import 'package:flutter/material.dart';
import 'package:test/test.dart';

void main() {
  test('测试配置Json格式转换', () {
    final config = AppConfig.defaultConfig();
    config.history.add({"name": "test", "history": [{"role": "user", "content": "你好"}]});
    config.lawCaches.add(LawCache("test", ["你好"]));
    final json = config.toJson();
    final config2 = AppConfig.fromJson(json);
    assert(config.textStyle == config2.textStyle);
    assert(config.serverConfigs.length == config2.serverConfigs.length);
    assert(config.history.length == config2.history.length);
    assert(config2.history[0]["name"] == "test");
    assert(config2.history[0]["history"][0]["content"] == "你好");
    assert(config2.lawCaches.length == 1);
    assert(config2.lawCaches[0].name == "test");
    assert(config2.lawCaches[0].laws.length == 1);
    assert(config2.lawCaches[0].laws[0] == "你好");
  });
}
