import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../widgets/app_icon_button.dart';

class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.palette,
    required this.primaryLabel,
    required this.onLibraryTap,
    required this.onBookmarksTap,
    required this.onSettingsTap,
    required this.onPrimaryTap,
    required this.onMoreTap,
  });

  final ReaderThemePalette palette;
  final String primaryLabel;
  final VoidCallback onLibraryTap;
  final VoidCallback onBookmarksTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onPrimaryTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.toolbar,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            AppIconButton(
              palette: palette,
              icon: Icons.library_books_outlined,
              label: '书架',
              onTap: onLibraryTap,
            ),
            AppIconButton(
              palette: palette,
              icon: Icons.bookmark_border_rounded,
              label: '书签',
              onTap: onBookmarksTap,
            ),
            AppIconButton(
              palette: palette,
              icon: Icons.text_fields_rounded,
              label: 'Aa',
              onTap: onSettingsTap,
            ),
            AppIconButton(
              palette: palette,
              icon: Icons.graphic_eq_rounded,
              label: primaryLabel,
              onTap: onPrimaryTap,
              emphasized: true,
            ),
            AppIconButton(
              palette: palette,
              icon: Icons.more_horiz_rounded,
              label: '更多',
              onTap: onMoreTap,
            ),
          ],
        ),
      ),
    );
  }
}
