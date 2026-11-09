// @file python_env.dart
// @brief Python 流水线桥接配置（开发期用外部 Python 子进程）
//
// 说明：
//  - 当前为 Windows 桌面调试阶段的配置：Flutter 通过 Process.run 调用外部
//    Python 解释器，运行仓库根 python/ 包内的 rag/build/tokenize 模块。
//  - 后续接入 serious_python（Android 内嵌）或推理服务器时，替换本文件常量
//    或改写 lib/services/chat_pipeline.dart 的调用实现即可，UI 不受影响。

import 'dart:io';

/// Python 解释器路径（需已安装 python/requirements.txt 中的依赖）。
/// 开发机默认使用 ChatLaw conda 环境；部署/其他机器请替换。
const String kPythonExe = r"C:\Users\qingxi\.conda\envs\ChatLaw_env\python.exe";

/// 资源根目录，对应 python 侧环境变量 APPDATA_DIR。
/// 内容需满足 docs/client_modules.md §6.2 的目录结构
/// （vectorstore/ 含 model.onnx、tokenizer/ 等）。
const String kAppDataDir = r"D:\dev\chatlaw_android_resources";

/// 仓库根路径（python/ 包所在目录）覆写。
/// 留空时使用 Directory.current —— 在仓库根执行 `flutter run -d windows`
/// 时即为仓库根；以其他 cwd 启动或打包发布时请显式填写。
const String kRepoRootOverride = "";

/// 实际使用的仓库根路径。
String get pythonRepoRoot {
  if (kRepoRootOverride.isNotEmpty) return kRepoRootOverride;
  return Directory.current.path;
}
