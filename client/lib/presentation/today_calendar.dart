import 'package:flutter/material.dart';

/// 只显示汇总日期所在月份；不把当前页任务数量冒充完整日程统计。
class TodayCalendar extends StatelessWidget {
  const TodayCalendar({required this.date, super.key});
  final String date;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.parse('${date}T00:00:00Z');
    final first = DateTime.utc(today.year, today.month);
    final count = DateTime.utc(today.year, today.month + 1, 0).day;
    return ExpansionTile(
      key: ValueKey('calendar-$date'),
      title: Text('${today.year} 年 ${today.month} 月 · 查看日历'),
      subtitle: Text('汇总日期：$date（北京时间）'),
      children: [
        const Text('仅标记汇总日期；完成操作或刷新会重新读取今日清单。'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          childAspectRatio: 1.6,
          children: [
            for (final day in ['一', '二', '三', '四', '五', '六', '日'])
              Center(child: Text(day)),
            for (var i = 0; i < first.weekday - 1; i++) const SizedBox(),
            for (var day = 1; day <= count; day++)
              Center(
                child: Semantics(
                  label: '$date 所在月 $day 日',
                  selected: day == today.day,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontWeight: day == today.day ? FontWeight.bold : null,
                      color: day == today.day
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
