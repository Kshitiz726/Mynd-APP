import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/utils/free_slots.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 9, 1, h, m);

void main() {
  group('mergeBusy', () {
    test('overlapping stretches become one', () {
      final m = mergeBusy([Busy(at(9), at(11)), Busy(at(10), at(12))]);
      expect(m.length, 1);
      expect(m.first.start, at(9));
      expect(m.first.end, at(12));
    });

    // 3-4 and 4-5 leave no usable minute between them. Treating that boundary
    // as a gap produces zero-length slots that pass a naive fits-check.
    test('touching stretches merge', () {
      final m = mergeBusy([Busy(at(15), at(16)), Busy(at(16), at(17))]);
      expect(m.length, 1);
      expect(m.first.end, at(17));
    });

    test('a stretch wholly inside another is swallowed', () {
      final m = mergeBusy([Busy(at(9), at(17)), Busy(at(12), at(13))]);
      expect(m.length, 1);
      expect(m.first.end, at(17));
    });

    test('separate stretches stay separate and come back in order', () {
      final m = mergeBusy([Busy(at(16), at(17)), Busy(at(9), at(10))]);
      expect(m.map((b) => b.start).toList(), [at(9), at(16)]);
    });

    test('a backwards stretch is dropped rather than trusted', () {
      expect(mergeBusy([Busy(at(12), at(11))]), isEmpty);
    });
  });

  group('earliestFit', () {
    // Anj's case, exactly: a meeting from 4 to 5, an hour of work dumped at 3,
    // and the work must not land on the meeting.
    test('an hour of work at 3pm does not land on a 4pm meeting', () {
      final busy = mergeBusy([Busy(at(16), at(17), title: 'Meeting')]);
      final fit = earliestFit(
        from: at(15),
        length: const Duration(hours: 1),
        notAfter: at(22),
        busy: busy,
      );
      expect(fit, at(15));
    });

    test('work that would overlap is pushed past the meeting', () {
      final busy = mergeBusy([Busy(at(16), at(17), title: 'Meeting')]);
      final fit = earliestFit(
        from: at(15, 30),
        length: const Duration(hours: 1),
        notAfter: at(22),
        busy: busy,
      );
      expect(fit, at(17));
    });

    test('a task slots into a gap big enough to hold it', () {
      final busy = mergeBusy([Busy(at(9), at(10)), Busy(at(11), at(12))]);
      final fit = earliestFit(
        from: at(9),
        length: const Duration(minutes: 45),
        notAfter: at(18),
        busy: busy,
      );
      expect(fit, at(10));
    });

    test('a gap too small is skipped rather than squeezed into', () {
      final busy = mergeBusy([Busy(at(9), at(10)), Busy(at(10, 30), at(12))]);
      final fit = earliestFit(
        from: at(9),
        length: const Duration(hours: 1),
        notAfter: at(18),
        busy: busy,
      );
      expect(fit, at(12));
    });

    test('nothing fitting before the cutoff returns null, not a bad slot', () {
      final busy = mergeBusy([Busy(at(9), at(17))]);
      final fit = earliestFit(
        from: at(9),
        length: const Duration(hours: 2),
        notAfter: at(18),
        busy: busy,
      );
      expect(fit, isNull);
    });

    test('an empty calendar places at the cursor', () {
      expect(
        earliestFit(
          from: at(14),
          length: const Duration(hours: 1),
          notAfter: at(22),
          busy: const [],
        ),
        at(14),
      );
    });

    test('a stretch already behind the cursor is ignored', () {
      final busy = mergeBusy([Busy(at(9), at(10))]);
      expect(
        earliestFit(
          from: at(14),
          length: const Duration(hours: 1),
          notAfter: at(22),
          busy: busy,
        ),
        at(14),
      );
    });

    test('back-to-back meetings are cleared in one go', () {
      final busy = mergeBusy([
        Busy(at(9), at(10)),
        Busy(at(10), at(11)),
        Busy(at(11), at(12)),
      ]);
      expect(
        earliestFit(
          from: at(9),
          length: const Duration(minutes: 30),
          notAfter: at(18),
          busy: busy,
        ),
        at(12),
      );
    });
  });

  group('freeBetween', () {
    test('gaps around a meeting', () {
      final free = freeBetween(at(9), at(18), [Busy(at(16), at(17))]);
      expect(free.length, 2);
      expect(free.first.start, at(9));
      expect(free.first.end, at(16));
      expect(free.last.start, at(17));
      expect(free.last.end, at(18));
    });

    test('a day booked solid has no gaps', () {
      expect(freeBetween(at(9), at(17), [Busy(at(8), at(18))]), isEmpty);
    });

    test('an empty calendar is one long gap', () {
      final free = freeBetween(at(9), at(17), const []);
      expect(free.length, 1);
      expect(free.first.length, const Duration(hours: 8));
    });

    test('a window that ends before it starts has no gaps', () {
      expect(freeBetween(at(17), at(9), const []), isEmpty);
    });
  });
}
