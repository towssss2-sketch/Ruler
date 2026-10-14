import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阶段信息由 Provider 管理，为后续应用层用例保留边界。
final stageProvider = Provider<String>((ref) => '阶段 0 · 工程与 CI 基座');
