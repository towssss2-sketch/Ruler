import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../infrastructure/memory_ingestion.dart';

/// 生命周期跟随应用 ProviderScope，返回列表不清空；关闭应用后不持久保存。
final experienceIngestionProvider = Provider<MemoryIngestion>(
  (ref) => MemoryIngestion(),
);
