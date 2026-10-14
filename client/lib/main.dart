import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/ruler_app.dart';

/// 启动离线欢迎页；阶段 0 不接收或上传任何案件资料。
void main() {
  runApp(const ProviderScope(child: RulerApp()));
}
