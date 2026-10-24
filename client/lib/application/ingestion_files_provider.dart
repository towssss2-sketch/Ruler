import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/ingestion_files.dart';
import '../infrastructure/api_ingestion_files.dart';
import '../infrastructure/api_repository.dart';
import '../infrastructure/storage_transfer.dart';
import 'documents_provider.dart';
import 'online_provider.dart';

/// 文件连接随页面/账号释放，不跨会话保存票据或签名。
final ingestionFilesProvider = Provider.autoDispose<IngestionFiles?>((ref) {
  final repository = ref.watch(onlineProvider);
  if (repository is! ApiRepository) return null;
  final files = ApiIngestionFiles(
    repository.session,
    StorageTransfer(ref.watch(storageOriginsProvider)),
  );
  ref.onDispose(files.close);
  return files;
});
