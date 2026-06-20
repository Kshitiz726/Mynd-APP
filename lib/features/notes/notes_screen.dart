import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/notes_provider.dart';
import '../../widgets/om_screen_header.dart';
import '../../widgets/om_tappable.dart';
import 'note_editor_screen.dart';

/// "Notebook" — a calm, searchable home for thoughts: pinned notes up top,
/// recent notes below, and a quick-capture FAB. Mirrors the prototype's
/// `#screen-notebook`.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<NotesProvider>().fetchNotes());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Scaffold(
      floatingActionButton: OmTappable(
        feedback: OmTapFeedback.medium,
        pressedScale: 0.88,
        onTap: () {
          Haptics.medium();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoteEditorScreen()));
        },
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(c.accent, Colors.white, 0.18)!, c.accent],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: c.accent.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Icon(OmIcons.byName('plus'), color: Colors.white, size: 28),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
          children: [
            const OmScreenHeader(title: 'Notebook', subtitle: 'your safe harbor for thoughts'),
            const SizedBox(height: AppSpacing.lg),
            _SearchField(),
            const SizedBox(height: AppSpacing.xl),
            
            Consumer<NotesProvider>(
              builder: (context, provider, _) {
                if (provider.loading && provider.allNotes.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final pinned = provider.pinnedNotes;
                final recent = provider.recentNotes;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pinned.isNotEmpty) ...[
                      Text('pinned', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        height: 152,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: pinned.length,
                          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
                          itemBuilder: (context, idx) {
                            final note = pinned[idx];
                            return SizedBox(
                              width: 160,
                              child: _PinnedNote(
                                tag: note.tags.isNotEmpty ? '#${note.tags.first}' : '#Note',
                                title: note.title,
                                preview: note.preview,
                                tint: const Color(0xFFDCE3EC),
                                titleColor: const Color(0xFF36506E),
                                onPinToggle: () => provider.togglePin(note),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],

                    if (recent.isNotEmpty || pinned.isEmpty) ...[
                      Text('recent', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.md),
                      if (recent.isEmpty && pinned.isEmpty)
                        const Text('No notes found.')
                      else
                        ...recent.map((note) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _RecentNote(
                            iconName: 'file-text',
                            iconTint: const Color(0xFFEADFD0),
                            iconColor: const Color(0xFF9A7B4F),
                            title: note.title,
                            meta: 'Today',
                            onPinToggle: () => provider.togglePin(note),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
                            ),
                          ),
                        )),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return TextField(
      onChanged: (val) => context.read<NotesProvider>().search(val),
      cursorColor: c.primary,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search notes, tags…',
        hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.text2),
        prefixIcon: Icon(OmIcons.byName('search'), size: 20, color: c.text2),
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
      ),
    );
  }
}

class _PinnedNote extends StatelessWidget {
  const _PinnedNote({
    required this.tag,
    required this.title,
    required this.preview,
    required this.tint,
    required this.titleColor,
    required this.onPinToggle,
    required this.onTap,
  });

  final String tag;
  final String title;
  final String preview;
  final Color tint;
  final Color titleColor;
  final VoidCallback onPinToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tintAdj = context.isDark ? Color.lerp(tint, Colors.black, 0.55)! : tint;
    final titleAdj = context.isDark ? Color.lerp(titleColor, Colors.white, 0.35)! : titleColor;
    return OmTappable(
      pressedScale: 0.96,
      feedback: OmTapFeedback.light,
      onTap: onTap, 
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tintAdj,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(tag,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: titleAdj,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      )),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: titleAdj,
                    fontSize: 17,
                    height: 1.15,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: titleAdj.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentNote extends StatelessWidget {
  const _RecentNote({
    required this.iconName,
    required this.iconTint,
    required this.iconColor,
    required this.title,
    required this.meta,
    required this.onPinToggle,
    required this.onTap,
  });

  final String iconName;
  final Color iconTint;
  final Color iconColor;
  final String title;
  final String meta;
  final VoidCallback onPinToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      pressedScale: 0.98,
      feedback: OmTapFeedback.light,
      onTap: onTap, 
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.isDark ? c.surfaceAlt : iconTint,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Icon(OmIcons.byName(iconName), size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(meta, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Icon(OmIcons.byName('chevR'), size: 18, color: c.text2),
          ],
        ),
      ),
    );
  }
}
