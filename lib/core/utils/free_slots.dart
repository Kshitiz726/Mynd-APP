/// Finding room in a day that already has things in it.
///
/// Pulled out as plain functions with no plugin behind them, because this is
/// the part that decides whether the app double-books somebody. A wrong answer
/// here is a task laid on top of a meeting, which is worse than the app not
/// scheduling at all: an empty slot is obvious, a hidden clash is discovered
/// when you miss the meeting.
library;

/// A stretch of time that is already taken.
class Busy {
  const Busy(this.start, this.end, {this.title});

  final DateTime start;
  final DateTime end;

  /// Only for explaining a decision to somebody ("moved past Standup"). Never
  /// used in the arithmetic.
  final String? title;

  bool get valid => end.isAfter(start);

  Duration get length => end.difference(start);

  @override
  String toString() => 'Busy(${start.toIso8601String()}..${end.toIso8601String()})';
}

/// Sort by start and fold overlapping or touching stretches into one.
///
/// Calendars routinely hand back overlapping events (a meeting inside a
/// blocked-out morning, two invitations at once). Walking those unmerged means
/// a gap can be "found" inside a stretch that another event still covers, so
/// everything downstream assumes this has been run first.
///
/// Touching stretches merge too: a 3-4 and a 4-5 leave no usable minute
/// between them, and treating that boundary as a gap produces zero-length
/// slots that pass a naive fits-check.
List<Busy> mergeBusy(Iterable<Busy> input) {
  final all = [
    for (final b in input)
      if (b.valid) b,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (all.isEmpty) return const [];

  final out = <Busy>[all.first];
  for (final b in all.skip(1)) {
    final last = out.last;
    if (!b.start.isAfter(last.end)) {
      if (b.end.isAfter(last.end)) {
        out[out.length - 1] = Busy(last.start, b.end, title: last.title);
      }
      continue;
    }
    out.add(b);
  }
  return out;
}

/// The earliest moment at or after [from] where [length] fits with nothing in
/// the way, or null when it does not fit before [notAfter].
///
/// [busy] must already be merged. The walk is forward-only: it never looks for
/// a gap behind the cursor, because tasks are laid in an order somebody chose
/// and reaching backwards to fill a hole would silently reorder their day.
DateTime? earliestFit({
  required DateTime from,
  required Duration length,
  required DateTime notAfter,
  required List<Busy> busy,
}) {
  var cursor = from;
  for (final b in busy) {
    // Already past this one.
    if (!b.end.isAfter(cursor)) continue;
    // The gap before it: usable only if the whole task fits inside.
    if (b.start.difference(cursor) >= length) break;
    // Otherwise start after it and keep looking.
    cursor = b.end;
  }
  if (cursor.add(length).isAfter(notAfter)) return null;
  return cursor;
}

/// What is free between [from] and [to], given what is taken.
///
/// Used for showing somebody where their day actually has room rather than for
/// placing anything, so it returns every gap including very short ones. A
/// caller that needs a minimum filters on [Busy.length].
List<Busy> freeBetween(DateTime from, DateTime to, List<Busy> busy) {
  if (!to.isAfter(from)) return const [];
  final out = <Busy>[];
  var cursor = from;
  for (final b in mergeBusy(busy)) {
    if (!b.end.isAfter(cursor)) continue;
    if (!b.start.isBefore(to)) break;
    if (b.start.isAfter(cursor)) out.add(Busy(cursor, b.start));
    cursor = b.end;
    if (!cursor.isBefore(to)) return out;
  }
  if (to.isAfter(cursor)) out.add(Busy(cursor, to));
  return out;
}
