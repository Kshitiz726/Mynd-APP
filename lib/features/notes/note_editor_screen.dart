import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../providers/notes_provider.dart';
import '../../widgets/om_screen_header.dart';
import '../../widgets/om_tappable.dart';
import '../../models/note.dart';
import '../../core/utils/om_icons.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.note});
  final Note? note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      Toast.show(context, 'Title and content cannot be empty');
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<NotesProvider>();
    final Note? result;
    if (widget.note != null) {
      result = await provider.updateNote(widget.note!.id, title, content, widget.note!.tags);
    } else {
      result = await provider.createNote(title, content, []);
    }
    setState(() => _saving = false);

    if (result != null && mounted) {
      Toast.show(context, 'Note saved');
      Navigator.pop(context);
    } else {
      Toast.show(context, 'Failed to save note');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH, vertical: AppSpacing.md),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OmTappable(
                    onTap: () => Navigator.pop(context),
                    child: Icon(OmIcons.byName('close'), color: c.text, size: 24),
                  ),
                  OmTappable(
                    onTap: _saving ? () {} : _save,
                    child: Text('Save', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.primary)),
                  )
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _titleController,
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c.text2),
                  border: InputBorder.none,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _contentController,
                  maxLines: null,
                  expands: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Write your thoughts...',
                    hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.text2),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
