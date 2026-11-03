import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utilities/utilities.dart';

/// Validated build-time configuration. Overridden in `main()`; reading it
/// before that is a programming error.
final clientConfigProvider = Provider<ClientConfig>(
  (ref) =>
      throw StateError('clientConfigProvider must be overridden in main().'),
);
