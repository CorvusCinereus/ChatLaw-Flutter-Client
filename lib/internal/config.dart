/**
 * @file config.dart
 * @brief 应用配置
 * @author CorvusCinereus
 */

import 'dart:convert';

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

  AppConfig(this.textStyle, this.serverConfigs, this.history);

  factory AppConfig.defaultConfig() =>
      AppConfig(TextStyle(fontSize: 19, color: Color(0xFF4A4A4A)), [], []);

  /// @brief 应用配置转换为 JSON 格式
  /// @return JSON 格式的应用配置
  Map<String, dynamic> toJson() {
    return {
      'text_style': {
        'font_size': textStyle.fontSize,
        'color': textStyle.color?.toARGB32() ?? Colors.black.toARGB32(),
      },
      'server_configs': serverConfigs.map((e) => e.toJson()).toList(),
      'history': history.map((e) => jsonEncode(e)).toList(),
    };
  }

  /// @brief 应用配置从 JSON 格式解析
  /// @param json JSON 格式的应用配置
  /// @return 应用配置实例
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      TextStyle(
        fontSize: json['text_style']['font_size'],
        color: Color(json['text_style']['color']),
      ),
      (json['server_configs'] as List<dynamic>)
          .map((e) => ServerConfig.fromJson(e))
          .toList(),
      (json['history'] as List<dynamic>)
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
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
    return ServerConfig(json['name'], json['address']);
  }
}
