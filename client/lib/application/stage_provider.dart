import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阶段信息由 Provider 管理，为后续应用层用例保留边界。
final stageProvider = Provider<String>((ref) => '阶段 11A1 · 客户端虚构体验');
