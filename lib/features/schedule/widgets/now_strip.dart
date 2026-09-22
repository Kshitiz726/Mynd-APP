import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/task.dart';
import '../../../providers/task_provider.dart';

/// Where the clock actually is in the day.
///
/// A timeline answers "what is the shape of today". It does not answer "what
/// am I meant to be doing at this exact minute", which for an ADHD user is the
/// only question that matters and the hardest one to hold. Reading it off a
/// column of blocks means finding the current time first, and finding the
/// current time is the thing that has already gone wrong.
///
/// So this says it outright, with a bar that fills as the block runs down. When
/// nothing is scheduled it collapses to nothing rather than announcing that
/// nothing is scheduled: an empty day does not need a badge.
class NowStrip extends StatefulWidget {
  const NowStrip({super.key});

  @override
  State<NowStrip> createState() => _NowStripState();
}

class _NowStripState extends State<NowStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Half a minute. The bar moves a pixel at a time on a normal block, which
    // is enough to read as live without waking the screen up every second.
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskProvider>();

    // Only ever about today. Browsing to next Tuesday should not claim
    // something is happening now.
    if (!tasks.viewingToday) return const SizedBox.shrink();

    final now = DateTime.now();
    final current = tasks.nowBlock;
    if (current != null) return _Running(task: current, now: now);

    final next = tasks.upNext;
    if (next?.startTime != null && next!.startTime!.isAfter(now)) {
      return _Upcoming(task: next, now: now);
    }
    return const SizedBox.shrink();
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final start = task.startTime!;
    final end = task.endTime ?? start.add(const Duration(hours: 1));
    final total = end.difference(start).inSeconds;
    final gone = now.difference(start).inSeconds;
    final progress = total <= 0 ? 0.0 : (gone / total).clamp(0.0, 1.0);
    final left = end.difference(now);

    final colour = task.isGoalTask ? c.primary : task.energy.color(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colour.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(colour: colour),
              const SizedBox(width: 8),
              Text(
                'HAPPENING NOW',
                style: TextStyle(
                  color: colour,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${DateFormat.jm().format(start)} – '
                '${DateFormat.jm().format(end)}',
                style: TextStyle(color: c.text2, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colour.withValues(alpha: 0.16),
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _remaining(left),
            style: TextStyle(
                color: c.text2, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Rounded up, never down. "0 minutes left" on something with 40 seconds to
  /// run is the kind of small lie that makes a clock feel broken.
  static String _remaining(Duration d) {
    if (d.inSeconds <= 0) return 'wrapping up';
    final mins = (d.inSeconds / 60).ceil();
    if (mins < 60) return '$mins min left';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h hr left' : '$h hr $m min left';
  }
}

class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final start = task.startTime!;
    final until = start.difference(now);
    final mins = (until.inSeconds / 60).ceil();
    final when = mins < 60
        ? 'in $mins min'
        : 'at ${DateFormat.jm().format(start)}';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 17, color: c.text2),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: 14.5, color: c.text2, fontWeight: FontWeight.w600),
                children: [
                  const TextSpan(text: 'next up, '),
                  TextSpan(text: when),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: task.title,
                    style: TextStyle(
                        color: c.text, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live dot. Static on purpose: this sits above a progress bar that is
/// already moving, and two things pulsing at different rates reads as a glitch.
class _Dot extends StatelessWidget {
  const _Dot({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      );
}
