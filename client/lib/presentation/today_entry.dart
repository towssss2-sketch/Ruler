import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/experience_provider.dart';
import '../domain/online.dart';
import '../infrastructure/experience_today.dart';
import 'experience_detail_page.dart';
import 'online_tasks_page.dart';
import 'today_page.dart';

/// 通过授权详情取得案件信息；不为每张卡预读全部当事人或猜测案号。
Future<void> openOnlineToday(
  BuildContext context,
  OnlineRepository repository,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (routeContext) => TodayPage(
      load: (page) => repository.today(page: page),
      complete: (task) => repository.setTaskDone(task.id, true),
      openCase: (task) async {
        final detail = await repository.caseDetail(task.caseId);
        if (!routeContext.mounted) return;
        final fields = detail.fields;
        await Navigator.of(routeContext).push(
          MaterialPageRoute<void>(
            builder: (_) => OnlineTasksPage(
              repository: repository,
              item: OnlineCase(
                detail.id,
                fields.caseNo,
                fields.cause,
                fields.court,
                stage: fields.stage,
                status: fields.status,
              ),
            ),
          ),
        );
      },
    ),
  ),
);

Future<void> openExperienceToday(BuildContext context, WidgetRef ref) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => TodayPage(
          offline: true,
          load: (page) async => experienceToday(
            await ref.read(experienceRepositoryProvider).load(),
            DateTime.now(),
            page,
          ),
          complete: (task) => ref
              .read(experienceProvider.notifier)
              .completeTask(task.caseId, task.id),
          openCase: (task) async {
            await Navigator.of(routeContext).push(
              MaterialPageRoute<void>(
                builder: (detailContext) => ExperienceDetailPage(
                  caseId: task.caseId,
                  onBack: () => Navigator.of(detailContext).pop(),
                ),
              ),
            );
          },
        ),
      ),
    );
