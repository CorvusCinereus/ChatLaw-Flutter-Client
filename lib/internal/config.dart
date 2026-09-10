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

/// 服务器默认 IP（与 chatlaw/config.yaml 的 SERVER_IP 默认值保持一致）
///
/// 端口由服务端固定（心跳 6005 / 数据 6006），客户端只需填写 IP。
const String kDefaultServerHost = '192.168.137.99';

class ServerConfig {
  String name;

  /// 服务器 IP / 主机名。兼容历史上存成 URL 的形式，取值请用 [host]。
  String address;

  ServerConfig(this.name, this.address);

  factory ServerConfig.defaultConfig() =>
      ServerConfig('默认', kDefaultServerHost);

  /// 仅取主机部分：兼容旧配置存成 `http://host:port/...` 的情况，
  /// 端口一律使用服务端固定的 6005/6006。
  String get host {
    var s = address.trim();
    final scheme = s.indexOf('://');
    if (scheme != -1) s = s.substring(scheme + 3);
    final slash = s.indexOf('/');
    if (slash != -1) s = s.substring(0, slash);
    final colon = s.indexOf(':');
    if (colon != -1) s = s.substring(0, colon);
    return s;
  }

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
  List<String> details;

  LawCache(this.name, this.laws, this.details);

  factory LawCache.fromJson(Map<String, dynamic> json) {
    final laws = json['laws'] as List? ?? [];
    final details = json['details'] as List? ?? [];
    return LawCache(
      json['name'] as String? ?? '',
      laws.whereType<String>().toList(),
      details.whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'laws': laws, 'details': details};
  }
}
