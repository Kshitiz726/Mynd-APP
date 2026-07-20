import 'package:flutter/material.dart';

/// Owns a [TextEditingController] for exactly as long as its subtree is mounted.
///
/// Sheets must not create a controller, `await showModalBottomSheet(...)`, then
/// dispose it: that future completes when the pop *begins*, not when the sheet
/// has finished animating out. The field is still mounted and still rebuilding
/// — the closing keyboard changes the view insets every frame — so the next
/// rebuild reaches a controller that no longer exists and throws
/// "A TextEditingController was used after being disposed", taking the whole
/// screen down with it.
///
/// Owning the controller in a [State] ties disposal to the route's real
/// teardown, which is the only moment nothing can rebuild against it.
class TextEditingScope extends StatefulWidget {
  const TextEditingScope({super.key, this.text, required this.builder});

  /// Initial text, for sheets that open pre-filled.
  final String? text;

  final Widget Function(BuildContext context, TextEditingController controller) builder;

  @override
  State<TextEditingScope> createState() => _TextEditingScopeState();
}

class _TextEditingScopeState extends State<TextEditingScope> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
