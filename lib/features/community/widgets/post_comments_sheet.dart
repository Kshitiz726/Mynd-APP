import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../models/community/post.dart';
import '../../../widgets/om_avatar.dart';
import '../../../widgets/om_button.dart';

class PostCommentsSheet extends StatefulWidget {
  const PostCommentsSheet({super.key, required this.post});

  final Post post;

  static Future<void> show(BuildContext context, Post post) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => PostCommentsSheet(post: post),
    );
  }

  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  List<PostComment>? _comments;
  bool _loading = true;
  bool _sending = false;
  PostComment? _replyingTo;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await ApiClient.instance.fetchComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ApiClient.instance.addComment(widget.post.id, body, parentId: _replyingTo?.id);
      _ctrl.clear();
      _replyingTo = null;
      _focus.unfocus();
      Haptics.success();
      await _load(); // Reload to see the new comment
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleUpvote(int index) async {
    final comment = _comments![index];
    final active = !comment.hasUpvoted;
    setState(() {
      _comments![index] = comment.copyWith(
        hasUpvoted: active,
        upvoteCount: comment.upvoteCount + (active ? 1 : -1),
      );
    });
    Haptics.light();
    try {
      await ApiClient.instance.toggleCommentUpvote(comment.id, active);
    } catch (_) {
      // Revert on failure
      if (mounted) {
        setState(() {
          _comments![index] = comment;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Comments', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_comments == null || _comments!.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No comments yet. Be the first!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _comments!.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final comment = _comments![index];
                  final depth = (comment.path?.split('.').length ?? 1) - 1;
                  final leftPadding = (depth * 28.0).clamp(0.0, 84.0);

                  return Padding(
                    padding: EdgeInsets.only(left: leftPadding),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OmAvatar(
                          userId: comment.authorName,
                          fallbackInitial: comment.initial,
                          fallbackColor: Color(int.parse(comment.avatarColor.replaceFirst('#', '0xFF'))),
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    comment.authorName,
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                comment.body,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _replyingTo = comment);
                                      _focus.requestFocus();
                                    },
                                    child: Text(
                                      'Reply',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  GestureDetector(
                                    onTap: () => _toggleUpvote(index),
                                    child: Row(
                                      children: [
                                        Icon(
                                          comment.hasUpvoted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                          size: 14,
                                          color: comment.hasUpvoted ? c.error : c.text2,
                                        ),
                                        if (comment.upvoteCount > 0) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            '${comment.upvoteCount}',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: comment.hasUpvoted ? c.error : c.text2,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (_replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text('Replying to ${_replyingTo!.authorName}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: Icon(Icons.close, size: 14, color: c.text2),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _replyingTo != null ? 'Write a reply...' : 'Add a comment...',
                    hintStyle: TextStyle(color: c.text2),
                    filled: true,
                    fillColor: c.surfaceAlt,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 12),
              OmButton(
                expand: false,
                label: '',
                icon: _sending ? OmIcons.byName('refresh') : OmIcons.byName('send'),
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
