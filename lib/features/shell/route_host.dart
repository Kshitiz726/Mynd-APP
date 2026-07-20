import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/om_back_button.dart';

/// Hosts a former tab as a pushed route.
///
/// Focus and the coach were written to sit inside the shell's [Scaffold], so
/// they paint no background of their own. Pushed directly they render as a
/// transparent sheet with Home showing through, and there is no way back.
/// This supplies both: an opaque surface and a leading back control.
class RouteHost extends StatelessWidget {
  const RouteHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: OmBackButton(onTap: () => Navigator.of(context).maybePop()),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
