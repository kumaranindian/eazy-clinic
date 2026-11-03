import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'async_body.dart';
import 'paged_list.dart';
import 'ui_helpers.dart';

/// Page title row with optional trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EcSpacing.lg),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: EcSpacing.md,
        runSpacing: EcSpacing.sm,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: EcTypography.pageTitle),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: EcTypography.bodySecondary),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Titled card section.
class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EcSpacing.lg),
      child: EcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: EcTypography.subsectionTitle),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: EcSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Label/value rows.
class KeyValues extends StatelessWidget {
  const KeyValues(this.rows, {super.key});

  final List<(String, Object?)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EcSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 170,
                  child: Text(label, style: EcTypography.bodySecondary),
                ),
                Expanded(
                  child: value is Widget
                      ? Align(alignment: Alignment.centerLeft, child: value)
                      : SelectableText(
                          '${value ?? '—'}',
                          style: EcTypography.body,
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget statusChip(Object? status) =>
    EcStatusChip(label: Fmt.humanize(status), tone: Fmt.tone(status));

/// Runs an admin action with progress, success and error feedback.
Future<bool> runAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String success,
  VoidCallback? after,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
    after?.call();
    return true;
  } on ApiFailure catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(failureText(e)), backgroundColor: EcColors.error),
    );
    return false;
  }
}

/// Search + filter + load-more list used by every admin list screen.
class ListScreen extends ConsumerStatefulWidget {
  const ListScreen({
    required this.title,
    required this.path,
    required this.rowBuilder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.subtitle,
    this.statusOptions,
    this.searchHint,
    this.searchParam = 'q',
    this.extraDropdown,
    this.extraText,
    this.extraParams = const {},
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final String path;
  final Widget Function(BuildContext context, Map<String, Object?> row)
  rowBuilder;
  final String emptyTitle;
  final String emptyMessage;
  final List<String>? statusOptions;
  final String? searchHint;

  /// Query parameter that carries the search text.
  final String searchParam;

  /// Optional second dropdown filter: (label, query param, values).
  final (String, String, List<String>)? extraDropdown;

  /// Optional free-text filter: (label, query param).
  final (String, String)? extraText;
  final Map<String, String> extraParams;
  final List<Widget> actions;

  @override
  ConsumerState<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends ConsumerState<ListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String? _status;
  String? _extraChoice;
  String _extraValue = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ListQuery(widget.path, {
      ...widget.extraParams,
      'status': _status ?? '',
      widget.searchParam: _q,
      if (widget.extraDropdown != null)
        widget.extraDropdown!.$2: _extraChoice ?? '',
      if (widget.extraText != null) widget.extraText!.$2: _extraValue,
    });
    final state = ref.watch(pagedListProvider(query));
    final notifier = ref.read(pagedListProvider(query).notifier);
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: widget.title,
          subtitle: widget.subtitle,
          actions: widget.actions,
        ),
        Wrap(
          spacing: EcSpacing.md,
          runSpacing: EcSpacing.md,
          children: [
            if (widget.searchHint != null)
              SizedBox(
                width: 320,
                child: EcSearchField(
                  hint: widget.searchHint!,
                  controller: _search,
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      if (mounted) setState(() => _q = v.trim());
                    });
                  },
                ),
              ),
            if (widget.statusOptions != null)
              SizedBox(
                width: 240,
                child: EcDropdown<String?>(
                  label: 'Status',
                  items: [null, ...widget.statusOptions!],
                  value: _status,
                  itemLabel: (s) =>
                      s == null ? 'All statuses' : Fmt.humanize(s),
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
            if (widget.extraDropdown != null)
              SizedBox(
                width: 240,
                child: EcDropdown<String?>(
                  label: widget.extraDropdown!.$1,
                  items: [null, ...widget.extraDropdown!.$3],
                  value: _extraChoice,
                  itemLabel: (s) => s == null ? 'All' : Fmt.humanize(s),
                  onChanged: (v) => setState(() => _extraChoice = v),
                ),
              ),
            if (widget.extraText != null)
              SizedBox(
                width: 240,
                child: EcTextField(
                  label: widget.extraText!.$1,
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      if (mounted) setState(() => _extraValue = v.trim());
                    });
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: EcSpacing.lg),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.all(EcSpacing.xxl),
            child: EcLoadingIndicator(),
          )
        else if (state.error != null && state.items.isEmpty)
          EcErrorState(
            title: state.error!.code?.httpStatus == 403
                ? 'Not permitted'
                : 'Could not load this list',
            message: state.error!.displayMessage,
            onRetry: state.error!.code?.httpStatus == 403
                ? null
                : notifier.refresh,
          )
        else if (state.items.isEmpty)
          EcEmptyState(title: widget.emptyTitle, message: widget.emptyMessage)
        else ...[
          for (final row in state.items)
            Padding(
              padding: const EdgeInsets.only(bottom: EcSpacing.sm),
              child: widget.rowBuilder(context, row),
            ),
          if (state.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: EcSpacing.md),
              child: EcSecondaryButton(
                label: 'Load more',
                isLoading: state.loadingMore,
                onPressed: notifier.loadMore,
              ),
            ),
        ],
      ],
    );
  }
}

/// A tappable list row card: title, subtitle, status chip.
class RowCard extends StatelessWidget {
  const RowCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.status,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Object? status;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EcCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: EcTypography.bodyStrong),
                const SizedBox(height: 2),
                Text(subtitle, style: EcTypography.bodySecondary),
              ],
            ),
          ),
          if (trailing != null) ...[
            Text(trailing!, style: EcTypography.bodySecondary),
            const SizedBox(width: EcSpacing.md),
          ],
          if (status != null) statusChip(status),
          const SizedBox(width: EcSpacing.xs),
          const Icon(Icons.chevron_right, color: EcColors.textSecondary),
        ],
      ),
    );
  }
}
