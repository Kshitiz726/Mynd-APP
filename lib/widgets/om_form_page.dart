import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import 'om_back_button.dart';

/// Presents a form as its own screen rather than a modal sheet.
///
/// A bottom sheet is the wrong container for anything with more than one text
/// field. The keyboard shoves the whole sheet up the screen, the content that
/// was under your thumb is suddenly at the top, tall forms overflow their own
/// box, and the page behind stays half-visible so nothing feels settled. Every
/// one of those was happening on the post composer, the goal form and the
/// focus setup.
///
/// A pushed route fixes all of it at once: the keyboard insets the scroll view
/// instead of moving the page, the content can be any height, and there is one
/// obvious way back.
///
/// Small, one-decision surfaces (the energy picker, the mood check-in, a
/// reaction picker) should stay sheets. The rule of thumb is whether it takes
/// typing: if it does, it wants a screen.
Future<T?> showOmFormPage<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,

  /// Pinned to the bottom above the keyboard, for the primary action. Left null
  /// when the form would rather place its own button inline.
  Widget Function(BuildContext)? footer,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (routeContext) => OmFormPage(
        title: title,
        subtitle: subtitle,
        footer: footer,
        child: Builder(builder: builder),
      ),
    ),
  );
}

class OmFormPage extends StatelessWidget {
  const OmFormPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget Function(BuildContext)? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Scaffold(
      backgroundColor: c.bg,
      // The form owns the whole screen, so the keyboard insets the scroll view
      // rather than translating the page.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, AppSpacing.screenH, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                        if (subtitle != null)
                          Text(subtitle!,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.xl),
                child: child,
              ),
            ),
            if (footer != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  8,
                  AppSpacing.screenH,
                  // Sits directly above the keyboard when one is up, so the
                  // primary action never hides behind it.
                  MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: footer!(context),
              ),
          ],
        ),
      ),
    );
  }
}
