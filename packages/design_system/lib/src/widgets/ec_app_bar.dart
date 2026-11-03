import 'package:flutter/material.dart';

/// Standard page app bar: white surface, navy title, hairline bottom border
/// (configured in [EcTheme]).
class EcAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EcAppBar({
    required this.title,
    this.actions,
    this.showBack = false,
    this.onBack,
    super.key,
  });

  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: actions,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            )
          : null,
    );
  }
}
