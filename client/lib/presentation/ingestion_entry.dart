import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/ingestion_files_provider.dart';
import '../application/documents_provider.dart';
import '../domain/ingestion.dart';
import 'ingestion_page.dart';

class OnlineIngestionEntry extends ConsumerWidget {
  const OnlineIngestionEntry({required this.repository, super.key});
  final IngestionRepository repository;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IngestionPage(
    repository: repository,
    attachments: ref.watch(ingestionFilesProvider),
    files: ref.watch(deviceFilesProvider),
  );
}
