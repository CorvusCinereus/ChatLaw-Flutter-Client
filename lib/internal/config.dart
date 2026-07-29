/**
 * @file config.dart
 * @brief 应用配置
 * @author CorvusCinereus
 */

import 'dart:io' show Platform;
import 'package:flutter/material.dart';

/**
 * @class AppConfig
 * @brief 应用配置类
 * @author CorvusCinereus
 */
class AppConfig {
  TextStyle textStyle;
  List<ServerConfig> serverConfigs;
  List<Map<String, dynamic>> history;
  List<LawCache> lawCaches;

  AppConfig(this.textStyle, this.serverConfigs, this.history, this.lawCaches);

  factory AppConfig.defaultConfig() => AppConfig(
    TextStyle(
      fontSize: Platform.isAndroid ? 14 : 19,
      color: const Color(0xFF4A4A4A),
      fontFamily: Platform.isWindows ? '微软雅黑' : null,
    ),
    [ServerConfig.defaultConfig()],
    [],
    [],
  );

  /// @brief 应用配置转换为 JSON 格式
  /// @return JSON 格式的应用配置
  Map<String, dynamic> toJson() {
    return {
      'text_style': {
        'font_size': textStyle.fontSize,
        'color': textStyle.color?.toARGB32() ?? Colors.black.toARGB32(),
        'font_family': textStyle.fontFamily,
      },
      'server_configs': serverConfigs.map((e) => e.toJson()).toList(),
      'history': history,
      'law_caches': lawCaches.map((e) => e.toJson()).toList(),
    };
  }

  /// @brief 应用配置从 JSON 格式解析
  /// @param json JSON 格式的应用配置
  /// @return 应用配置实例
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final textStyleData = json['text_style'] as Map<String, dynamic>? ?? {};
    final serverConfigs = json['server_configs'] as List? ?? [];
    final history = json['history'] as List? ?? [];
    final lawCaches = json['law_caches'] as List? ?? [];
    return AppConfig(
      TextStyle(
        fontSize: textStyleData['font_size'] as double? ?? 19.0,
        color: textStyleData['color'] != null
            ? Color(textStyleData['color'])
            : Color(0xFF4A4A4A),
        fontFamily:
            textStyleData['font_family'] as String? ??
            (Platform.isWindows ? '微软雅黑' : null),
      ),
      serverConfigs
          .whereType<Map<String, dynamic>>()
          .map((e) => ServerConfig.fromJson(e))
          .toList(),
      history.whereType<Map<String, dynamic>>().toList(),
      lawCaches
          .whereType<Map<String, dynamic>>()
          .map((e) => LawCache.fromJson(e))
          .toList(),
    );
  }
}

class ServerConfig {
  String name;
  String address;

  ServerConfig(this.name, this.address);

  factory ServerConfig.defaultConfig() =>
      ServerConfig('默认', 'http://localhost:8080');

  /// @brief 服务器配置转换为 JSON 格式
  /// @return JSON 格式的服务器配置
  Map<String, dynamic> toJson() {
    return {'name': name, 'address': address};
  }

  /// @brief 服务器配置从 JSON 格式解析
  /// @param json JSON 格式的服务器配置
  /// @return 服务器配置实例
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      json['name'] as String? ?? '',
      json['address'] as String? ?? '',
    );
  }
}

class LawCache {
  String name;
  List<String> laws;

  LawCache(this.name, this.laws);

  factory LawCache.fromJson(Map<String, dynamic> json) {
    return LawCache(
      json['name'] as String? ?? '',
      json['laws'] as List<String>? ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'laws': laws};
  }
}
