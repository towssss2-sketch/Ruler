import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/documents_provider.dart';
import '../domain/documents.dart';
import '../domain/online.dart';
import 'online_widgets.dart';

/// 服务端文件列表；分类和历史版本均来自真实接口。
class OnlineDocumentsPage extends ConsumerWidget {
  const OnlineDocumentsPage({required this.caseId, super.key});
  final String caseId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(documentsProvider);
    if (repository == null) {
      return const Scaffold(body: Center(child: Text('请重新登录。')));
    }
    return DocumentList(
      key: ObjectKey(repository),
      caseId: caseId,
      repository: repository,
    );
  }
}

class DocumentList extends StatefulWidget {
  const DocumentList({
    required this.caseId,
    required this.repository,
    super.key,
  });
  final String caseId;
  final DocumentRepository repository;
  @override
  State<DocumentList> createState() => _DocumentListState();
}

class _DocumentListState extends State<DocumentList> {
  bool _history = false;
  String? _category;
  int _page = 1;
  late Future<OnlinePage<CaseDocument>> _result = widget.repository.list(
    widget.caseId,
  );

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = widget.repository.list(
      widget.caseId,
      page: _page,
      category: _category,
      history: _history,
    );
  });

  Future<void> _remove(CaseDocument document) async {
    if (!await confirmOnlineDelete(
      context,
      '删除此文件版本？文件和占用容量仍保留，已有下载链接到期前可能有效。',
    )) {
      return;
    }
    if (!mounted) return;
    await widget.repository.remove(document.id);
    if (mounted) _load(1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('案件文件'),
      actions: [
        IconButton(
          tooltip: '刷新文件',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: _filters()),
          Expanded(
            child: OnlineResult(future: _result, retry: _load, render: _list),
          ),
        ],
      ),
    ),
  );

  Widget _filters() => Column(
    children: [
      DropdownButtonFormField<String>(
        initialValue: _category ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: '文件分类'),
        items: [
          const DropdownMenuItem(value: '', child: Text('全部分类')),
          ...documentCategories.entries.map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ),
        ],
        onChanged: (value) {
          _category = value == '' ? null : value;
          _load(1);
        },
      ),
      SwitchListTile(
        title: const Text('显示历史版本'),
        value: _history,
        onChanged: (value) {
          _history = value;
          _load(1);
        },
      ),
    ],
  );

  Widget _list(OnlinePage<CaseDocument> result) => Column(
    children: [
      Expanded(
        child: result.items.isEmpty
            ? const Center(child: Text('暂无符合条件的案件文件'))
            : ListView(children: result.items.map(_file).toList()),
      ),
      onlinePagination(result, _load),
    ],
  );

  Widget _file(CaseDocument file) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(file.name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${documentCategories[file.category]} · v${file.version} · '
            '${file.current ? '当前版本' : '历史版本'} · ${file.size} 字节',
          ),
          OnlineAction(label: '删除文件版本', run: () => _remove(file)),
        ],
      ),
    ),
  );
}
