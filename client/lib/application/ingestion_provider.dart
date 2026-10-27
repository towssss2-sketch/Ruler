import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../infrastructure/memory_ingestion.dart';
import '../infrastructure/memory_ingestion_preview.dart';

/// 生命周期跟随应用 ProviderScope，返回列表不清空；关闭应用后不持久保存。
final experienceIngestionProvider = Provider<MemoryIngestion>(
  (ref) => MemoryIngestion(),
);

/// 记录与虚构材料共享应用生命周期，返回列表不会丢失，关闭应用清除。
final experiencePreviewProvider = Provider<MemoryIngestionPreview>(
  (ref) => MemoryIngestionPreview(ref.watch(experienceIngestionProvider)),
);
