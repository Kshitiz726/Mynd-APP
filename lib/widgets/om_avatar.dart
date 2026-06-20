import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class OmAvatar extends StatelessWidget {
  const OmAvatar({
    super.key,
    required this.userId,
    required this.fallbackInitial,
    required this.fallbackColor,
    this.size = 40,
  });

  final String userId;
  final String fallbackInitial;
  final Color fallbackColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        'https://api.dicebear.com/7.x/bottts/png?seed=$userId&size=${(size * 2).toInt()}',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Text(
            fallbackInitial,
            style: TextStyle(
              color: fallbackColor,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
