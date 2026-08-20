import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import 'om_tappable.dart';

/// A calm, app-styled time picker used everywhere instead of Material's clock
/// dial (which read as a foreign, heavy control).
///
/// It shows a Cupertino-style spinning wheel inside one of the app's own bottom
/// sheets, with a header and a single "done" button - the same shape as every
/// other sheet in OurMynd, on both iOS and Android. Returns the chosen
/// [TimeOfDay], or null if dismissed.
Future<TimeOfDay?> showOmTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _OmTimePickerSheet(initial: initialTime, helpText: helpText),
  );
}

class _OmTimePickerSheet extends StatefulWidget {
  const _OmTimePickerSheet({required this.initial, this.helpText});

  final TimeOfDay initial;
  final String? helpText;

  @override
  State<_OmTimePickerSheet> createState() => _OmTimePickerSheetState();
}

class _OmTimePickerSheetState extends State<_OmTimePickerSheet> {
  late DateTime _value;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _value = DateTime(
        now.year, now.month, now.day, widget.initial.hour, widget.initial.minute);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.text2.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.helpText ?? 'Pick a time',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            // The wheel. Themed to the app rather than the platform default so it
            // matches in light and dark.
            SizedBox(
              height: 190,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: context.isDark ? Brightness.dark : Brightness.light,
                  primaryColor: c.primary,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: c.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: _value,
                  use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
                  onDateTimeChanged: (dt) {
                    Haptics.select();
                    _value = dt;
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: OmTappable(
                onTap: () {
                  Haptics.medium();
                  Navigator.of(context)
                      .pop(TimeOfDay(hour: _value.hour, minute: _value.minute));
                },
                feedback: OmTapFeedback.none,
                pressedScale: 0.97,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: c.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Text(
                    'done',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
