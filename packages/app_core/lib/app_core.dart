/// Shared authentication, session handling and API client for the three
/// EazyClinic apps. App-specific screens and business features live in the
/// apps; nothing here knows about clinics, patients or consultations.
library;

export 'src/api/api_client.dart';
export 'src/auth/application/auth_controller.dart';
export 'src/auth/application/auth_providers.dart';
export 'src/auth/application/auth_redirect.dart';
export 'src/auth/application/auth_router.dart';
export 'src/auth/data/dio_auth_api.dart';
export 'src/auth/data/firebase_auth_repository.dart';
export 'src/auth/domain/app_audience.dart';
export 'src/auth/domain/auth_api.dart';
export 'src/auth/domain/auth_failure.dart';
export 'src/auth/domain/auth_repository.dart';
export 'src/auth/domain/auth_state.dart';
export 'src/auth/domain/auth_user.dart';
export 'src/auth/presentation/auth_layout.dart';
export 'src/auth/presentation/auth_routes.dart';
export 'src/config/auth_ui_config.dart';
export 'src/config/firebase_bootstrap.dart';
