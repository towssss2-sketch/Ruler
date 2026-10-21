import 'case_detail_page.dart';
import '../domain/case_fields.dart';
import 'case_edit_dialog.dart';
import 'package:flutter/material.dart';
import '../domain/online.dart';
import 'online_form.dart';
import 'online_widgets.dart';
import 'online_documents_page.dart';

/// 单案常规任务工作页，所有操作等待服务端确认，不显示模拟文件。
class OnlineTasksPage extends StatefulWidget {
  const OnlineTasksPage({
    required this.repository,
    required this.item,
    super.key,
  });
  final OnlineRepository repository;
  final OnlineCase item;
  @override
  State<OnlineTasksPage> createState() => _OnlineTasksPageState();
}

class _OnlineTasksPageState extends State<OnlineTasksPage> {
  late OnlineCase _item = widget.item;
  int _page = 1;
  late Future<OnlinePage<OnlineTask>> _result = widget.repository.tasks(
    _item.id,
  );

  void _load([int? page]) => setState(() {
    _page = page ?? _page;
    _result = widget.repository.tasks(_item.id, page: _page);
  });

  Future<void> _add() async {
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (context) =>
          OnlineForm(repository: widget.repository, caseId: _item.id),
    );
    if (saved == true && mounted) _load(1);
  }

  Future<void> _edit() async {
    OnlineCase? updated;
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => CaseEditDialog(
        initial: _item.fields,
        save: (fields) async {
          updated = await widget.repository.updateCase(_item.id, fields);
        },
      ),
    );
    if (saved == true && mounted && updated != null) {
      setState(() => _item = updated!);
    }
  }

  Future<void> _deleteCase() async {
    if (!await confirmOnlineDelete(context, '删除此测试案件及其普通任务？服务端保留审计历史。')) return;
    if (!mounted) return;
    await widget.repository.removeCase(_item.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteTask(OnlineTask task) async {
    if (!await confirmOnlineDelete(context, '删除此工作任务？')) return;
    if (!mounted) return;
    await widget.repository.removeTask(task.id);
    if (mounted) _load(1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_item.caseNo),
      actions: [
        IconButton(
          tooltip: '刷新任务',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${_item.cause} · ${_item.court}\n${caseStages[_item.stage]} · ${caseStatuses[_item.status]}\n常规工作任务 · 工作日期不代表法定期间',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => OnlineDocumentsPage(caseId: _item.id),
                  ),
                ),
                child: const Text('案件文件'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CaseDetailPage(
                      load: () => widget.repository.caseDetail(_item.id),
                      checkConflicts: (page) =>
                          widget.repository.conflicts(_item.id, page: page),
                      saveParties: (parties) =>
                          widget.repository.saveParties(_item.id, parties),
                      saveSupplement: (value) =>
                          widget.repository.saveSupplement(_item.id, value),
                    ),
                  ),
                ),
                child: const Text('案件详情与当事人'),
              ),
              OnlineAction(label: '编辑案件信息', run: _edit),
              OnlineAction(label: '新增工作任务', run: _add),
              OnlineAction(label: '删除测试案件', run: _deleteCase),
            ],
          ),
          Expanded(
            child: OnlineResult(future: _result, retry: _load, render: _list),
          ),
        ],
      ),
    ),
  );

  Widget _list(OnlinePage<OnlineTask> result) => Column(
    children: [
      Expanded(
        child: result.items.isEmpty
            ? const Center(child: Text('暂无常规工作任务'))
            : ListView(
                children: result.items
                    .map(
                      (task) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${task.done ? '已完成' : '待办'} · ${task.dueDate ?? '未设工作日期'}',
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OnlineAction(
                                    key: ValueKey('${task.id}-${task.done}'),
                                    label: task.done ? '恢复待办' : '标记完成',
                                    run: () async {
                                      await widget.repository.setTaskDone(
                                        task.id,
                                        !task.done,
                                      );
                                      if (mounted) _load();
                                    },
                                  ),
                                  OnlineAction(
                                    label: '删除任务',
                                    run: () => _deleteTask(task),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
      onlinePagination(result, _load),
    ],
  );
}
