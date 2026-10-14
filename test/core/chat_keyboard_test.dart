import 'dart:io';

import 'package:flutter_test/flutter_test.dart';


/// The keyboard stayed up over the conversation and tapping anything else did
/// not put it away. Flutter only dismisses on a tap outside on desktop; on a
/// phone the field keeps focus until something takes it, and nothing did.
///
/// Asserted on the source, because the behaviour is two widget properties and
/// the alternative is a widget test that needs the whole provider tree and a
/// signed-in account to reach the composer at all.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the coach composer gives the keyboard up on a tap outside', () {
    final src = read('lib/features/coach/coach_screen.dart');
    expect(src, contains('onTapOutside'));
    expect(src, contains('ScrollViewKeyboardDismissBehavior.onDrag'),
        reason: 'dragging the conversation should dismiss the keyboard');
  });

  test('the community chat does the same', () {
    final src = read('lib/features/community/chat_screen.dart');
    expect(src, contains('onTapOutside'));
    expect(src, contains('ScrollViewKeyboardDismissBehavior.onDrag'));
  });
}
