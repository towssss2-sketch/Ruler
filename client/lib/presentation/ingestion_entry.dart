import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/ingestion_files_provider.dart';
import '../application/documents_provider.dart';
import '../domain/ingestion.dart';
import 'ingestion_page.dart';
import 'online_documents_page.dart';
import '../infrastructure/api_ingestion_archive.dart';
import '../application/online_provider.dart';
import '../infrastructure/api_repository.dart';
import '../infrastructure/api_ingestion_assignment.dart';

class OnlineIngestionEntry extends ConsumerWidget {
  const OnlineIngestionEntry({required this.repository, super.key});
  final IngestionRepository repository;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IngestionPage(
    repository: repository,
    attachments: ref.watch(ingestionFilesProvider),
    files: ref.watch(deviceFilesProvider),
    archive: switch (ref.watch(onlineProvider)) {
      ApiRepository api => ApiIngestionArchive(api.session),
      _ => null,
    },
    openCase: (item) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineDocumentsPage(caseId: item.id),
      ),
    ),
    assignment: switch (ref.watch(onlineProvider)) {
      ApiRepository api => ApiIngestionAssignment(api.session, api),
      _ => null,
    },
  );
}
