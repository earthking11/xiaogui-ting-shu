import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../models/bookmark.dart';

class BookmarkSheet extends StatelessWidget {
  const BookmarkSheet({
    super.key,
    required this.palette,
    required this.bookmarks,
    required this.onJump,
    required this.onDelete,
  });

  final ReaderThemePalette palette;
  final List<Bookmark> bookmarks;
  final ValueChanged<Bookmark> onJump;
  final ValueChanged<Bookmark> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '书签',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: palette.foreground),
              ),
              const SizedBox(height: 10),
              if (bookmarks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    '还没有书签，读到想停的地方时点一下就好。',
                    style: TextStyle(
                      color: palette.secondaryText,
                      fontSize: 15,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, index) =>
                        Divider(height: 1, color: palette.border),
                    itemBuilder: (context, index) {
                      final Bookmark bookmark = bookmarks[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${bookmark.percent.toStringAsFixed(1)}% 位置',
                          style: TextStyle(
                            color: palette.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          bookmark.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.secondaryText,
                            height: 1.5,
                          ),
                        ),
                        onTap: () => onJump(bookmark),
                        trailing: IconButton(
                          onPressed: () => onDelete(bookmark),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: palette.secondaryText,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
