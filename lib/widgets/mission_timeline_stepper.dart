import 'package:flutter/material.dart';

import '../models/mission_status.dart';

/// Horizontal mission progress for requester live view.
class MissionTimelineStepper extends StatelessWidget {
  final MissionStatus? current;
  final List<Map<String, dynamic>> events;

  const MissionTimelineStepper({
    super.key,
    required this.current,
    this.events = const [],
  });

  static const _labels = [
    'Created',
    'Pending',
    'Pitched',
    'Helper',
    'Accepted',
    'En route',
    'Arriving',
    'Done',
  ];

  int _activeIndex() {
    if (current == null) return 0;
    return current!.timelineIndex.clamp(0, MissionStatus.timelineOrder.length - 1);
  }

  DateTime? _timeForKey(String key) {
    for (final e in events) {
      if (e['event_key']?.toString() == key) {
        final raw = e['created_at']?.toString();
        if (raw != null) return DateTime.tryParse(raw);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _activeIndex();
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _labels.length,
        separatorBuilder: (_, __) => SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: 12,
              height: 2,
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        itemBuilder: (context, i) {
          final done = i <= active;
          final current = i == active;
          final status = MissionStatus.timelineOrder[i];
          final ts = _timeForKey(status.dbValue);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: current
                    ? BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Icon(
                  done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 22,
                  color: done ? scheme.primary : scheme.outlineVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[i],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: done ? FontWeight.w800 : FontWeight.w500,
                      color: done ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
              ),
              if (ts != null)
                Text(
                  '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
            ],
          );
        },
      ),
    );
  }
}
