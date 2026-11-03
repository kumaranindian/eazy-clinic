import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loading / error (with retry) / data rendering for an [AsyncValue].
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    required this.value,
    required this.onRetry,
    required this.builder,
    super.key,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const EcLoadingIndicator(),
      error: (e, _) => EcErrorState(
        title: e is ApiFailure && e.code?.httpStatus == 403
            ? 'Not permitted'
            : 'Could not load this page',
        message: e is ApiFailure ? e.displayMessage : 'Please try again.',
        onRetry: e is ApiFailure && e.code?.httpStatus == 403 ? null : onRetry,
      ),
      data: builder,
    );
  }
}

/// Shows an [ApiFailure] (including field issues) as an inline message.
String failureText(Object error) {
  if (error is! ApiFailure) return 'Something went wrong. Please try again.';
  if (error.issues.isEmpty) return error.displayMessage;
  return '${error.displayMessage} ${error.issues.map((i) => '${i.field}: ${i.message}').join(' · ')}';
}
