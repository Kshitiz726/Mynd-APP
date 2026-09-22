/// What somebody decided about an email their coach wants to send.
///
/// Sending is irreversible in a way almost nothing else in this app is: a
/// reminder set wrongly is a buzz at a bad time, an email sent wrongly is in
/// somebody else's inbox forever. So the default is to ask.
///
/// Asking every single time is its own failure though. Somebody who sends five
/// notes in a sitting and confirms all five has told you something, and making
/// them confirm the sixth is not caution, it is noise. Hence the middle
/// option, which is a decision about every future send rather than this one.
library;

enum EmailApproval {
  /// Send this one.
  allow,

  /// Send this one, and stop asking from now on.
  always,

  /// Do not send. The draft stays in the conversation.
  cancel,

  /// Send it, but not as written. [EmailDecision.instruction] says what to
  /// change, in the user's own words.
  change,
}

class EmailDecision {
  const EmailDecision(this.kind, {this.instruction});

  const EmailDecision.allow() : this(EmailApproval.allow);
  const EmailDecision.always() : this(EmailApproval.always);
  const EmailDecision.cancel() : this(EmailApproval.cancel);
  const EmailDecision.change(String what)
      : this(EmailApproval.change, instruction: what);

  final EmailApproval kind;

  /// Only set when [kind] is [EmailApproval.change].
  final String? instruction;
}
