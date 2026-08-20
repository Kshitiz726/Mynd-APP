import 'package:flutter/material.dart';

import '../core/services/api_config.dart';

/// Someone's face, wherever they appear.
///
/// The picture is fetched from the account rather than passed in, because the
/// URL is derivable from the user id alone. That is what lets this widget stay
/// a drop-in: a dozen call sites across community, chat, focus and body
/// doubling already had a user id and nothing else, and none of them had to
/// learn about avatars for every one of them to start showing real faces.
///
/// Falls back to the coloured initial when they have not set a picture, which
/// is also what the server returns for (404). It used to fall back to a
/// generated robot from dicebear, which is a stranger's face, not theirs.
class OmAvatar extends StatelessWidget {
  const OmAvatar({
    super.key,
    required this.userId,
    required this.fallbackInitial,
    required this.fallbackColor,
    this.size = 40,
    this.version,
  });

  final String userId;
  final String fallbackInitial;
  final Color fallbackColor;
  final double size;

  /// Changes when the picture does, to defeat the image cache. Optional: most
  /// call sites are showing other people, whose pictures change rarely enough
  /// that a stale one for a session is not worth the plumbing.
  final String? version;

  @override
  Widget build(BuildContext context) {
    final url = userId.isEmpty
        ? null
        : ApiConfig.instance
            .rest('/api/users/$userId/avatar${version == null ? '' : '?v=$version'}')
            .toString();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? _initial()
          : Image.network(
              url,
              fit: BoxFit.cover,
              // The endpoint is behind auth like everything else, so the image
              // request has to carry the token too.
              headers: ApiConfig.instance.authHeaders,
              // No picture set is the common case, not a failure worth showing.
              errorBuilder: (_, __, ___) => _initial(),
              // Nothing to show while it loads except the ground already
              // painted behind it. A spinner on a 40px circle is noise.
              frameBuilder: (_, child, frame, wasSync) =>
                  frame == null && !wasSync ? _initial() : child,
            ),
    );
  }

  Widget _initial() => Center(
        child: Text(
          fallbackInitial,
          style: TextStyle(
            color: fallbackColor,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.4,
          ),
        ),
      );
}
