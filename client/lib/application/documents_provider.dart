import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/documents.dart';
import '../infrastructure/api_documents.dart';
import '../infrastructure/api_repository.dart';
import '../infrastructure/storage_transfer.dart';
import 'online_provider.dart';

/// 对象存储源由构建配置给定；空值不授权任何对象存储连接。
final storageOriginsProvider = Provider<Set<String>>(
  (ref) => const String.fromEnvironment('RULER_STORAGE_ORIGINS')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet(),
);

/// 文件页面离开或账号变化时销毁传输连接，禁止跨会话复用签名。
final documentsProvider = Provider.autoDispose<DocumentRepository?>((ref) {
  final repository = ref.watch(onlineProvider);
  if (repository is! ApiRepository) return null;
  final documents = ApiDocuments(
    repository.session,
    StorageTransfer(ref.watch(storageOriginsProvider)),
  );
  ref.onDispose(documents.close);
  return documents;
});
