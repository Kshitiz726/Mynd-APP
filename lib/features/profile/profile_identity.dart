import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_tappable.dart';

/// The top of Settings: your picture, your name, and the two taps that change
/// them.
///
/// Both were previously assigned to people rather than chosen by them - a
/// generated handle like SilentHarbor49 and a robot avatar - which is fine for
/// an anonymous feed and wrong the moment you are sitting in a focus room with
/// someone you know.
class ProfileIdentity extends StatefulWidget {
  const ProfileIdentity({super.key, this.trailing});

  /// Anything that belongs under the name, e.g. the membership tag.
  final Widget? trailing;

  @override
  State<ProfileIdentity> createState() => _ProfileIdentityState();
}

class _ProfileIdentityState extends State<ProfileIdentity> {
  /// Bumped after a successful upload so the new picture is fetched instead of
  /// the one already in the image cache under the same URL.
  String? _avatarVersion;

  bool _busy = false;

  String get _name => ApiConfig.instance.displayName ?? 'your account';

  Future<void> _pickPicture(ImageSource source) async {
    try {
      // Resized on the phone rather than the server: a 12MP camera photo is
      // ~4MB, and none of that survives being drawn into a 92px circle.
      final shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (shot == null) return; // they backed out of the picker

      setState(() => _busy = true);
      final bytes = await shot.readAsBytes();
      await ApiClient.instance.uploadAvatar(bytes);

      // Every OmAvatar in the app builds the same URL for this user, so the
      // cached copy has to go or the old face survives until the next launch.
      await _forgetCachedAvatar();
      if (!mounted) return;
      setState(() {
        _avatarVersion = DateTime.now().millisecondsSinceEpoch.toString();
        _busy = false;
      });
      Haptics.medium();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, 'could not update your picture');
      debugPrint('[profile] avatar upload failed: $e');
    }
  }

  Future<void> _removePicture() async {
    try {
      setState(() => _busy = true);
      await ApiClient.instance.removeAvatar();
      await _forgetCachedAvatar();
      if (!mounted) return;
      setState(() {
        _avatarVersion = DateTime.now().millisecondsSinceEpoch.toString();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, 'could not remove your picture');
      debugPrint('[profile] avatar removal failed: $e');
    }
  }

  Future<void> _forgetCachedAvatar() async {
    final id = ApiConfig.instance.userId;
    if (id == null) return;
    await NetworkImage(
      ApiConfig.instance.rest('/api/users/$id/avatar').toString(),
      headers: ApiConfig.instance.authHeaders,
    ).evict();
  }

  Future<void> _choosePictureSource() async {
    Haptics.light();
    final c = context.omColors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text2.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            _SheetRow(
              icon: OmIcons.byName('camera'),
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(sheet);
                _pickPicture(ImageSource.camera);
              },
            ),
            _SheetRow(
              icon: OmIcons.byName('image'),
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(sheet);
                _pickPicture(ImageSource.gallery);
              },
            ),
            _SheetRow(
              icon: OmIcons.byName('trash'),
              label: 'Remove picture',
              destructive: true,
              onTap: () {
                Navigator.pop(sheet);
                _removePicture();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editName() async {
    Haptics.light();
    final controller = TextEditingController(text: _name);
    final c = context.omColors;

    final saved = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'what should people call you',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final name = saved?.trim() ?? '';
    if (name.isEmpty || name == _name) return;
    // Matches the server's own bounds, so the common mistake is caught here
    // instead of coming back as a 400 the user has to interpret.
    if (name.length < 2) {
      if (mounted) Toast.show(context, 'a name needs at least 2 characters');
      return;
    }

    try {
      setState(() => _busy = true);
      await ApiClient.instance.updateDisplayName(name);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, 'could not save that name');
      debugPrint('[profile] name change failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final handle = ApiConfig.instance.handle;
    final name = _name;

    return Center(
      child: Column(
        children: [
          OmTappable(
            onTap: _busy ? null : _choosePictureSource,
            feedback: OmTapFeedback.light,
            pressedScale: 0.96,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                OmAvatar(
                  userId: ApiConfig.instance.userId ?? '',
                  fallbackInitial: name.isNotEmpty ? name[0].toUpperCase() : '?',
                  fallbackColor: c.primary,
                  size: 92,
                  version: _avatarVersion,
                ),
                // A small camera badge, so the picture reads as something you
                // can change rather than something you were given.
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 2),
                  ),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(OmIcons.byName('camera'),
                          size: 14, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OmTappable(
            onTap: _busy ? null : _editName,
            feedback: OmTapFeedback.light,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 20)),
                const SizedBox(width: 6),
                Icon(OmIcons.byName('pencil'), size: 15, color: c.text2),
              ],
            ),
          ),
          if (handle != null) ...[
            const SizedBox(height: 3),
            Text(handle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.text2)),
          ],
          if (widget.trailing != null) ...[
            const SizedBox(height: 8),
            widget.trailing!,
          ],
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tint = destructive ? c.error : c.text;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: tint),
            const SizedBox(width: 14),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}
