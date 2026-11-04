import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/portal_repository.dart';
import '../push/push_service.dart';
import 'providers.dart';
import 'ui_kit.dart';

/// Navigation frame of the patient app (Home, Appointments, Records, Clinics,
/// Profile). It only decides what to show; the backend authorizes every call.
class PatientShell extends ConsumerWidget {
  const PatientShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  static const _items = <(String, EcNavDestination)>[
    ('/', EcNavDestination(label: 'Home', icon: Icons.home_outlined)),
    (
      '/appointments',
      EcNavDestination(label: 'Appointments', icon: Icons.event_outlined),
    ),
    (
      '/records',
      EcNavDestination(label: 'Records', icon: Icons.folder_shared_outlined),
    ),
    (
      '/clinics',
      EcNavDestination(label: 'Clinics', icon: Icons.local_hospital_outlined),
    ),
    (
      '/profile',
      EcNavDestination(label: 'Profile', icon: Icons.person_outline),
    ),
  ];

  int get _selected {
    for (var i = _items.length - 1; i > 0; i--) {
      if (location.startsWith(_items[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => EcNavScaffold(
    destinations: [for (final i in _items) i.$2],
    selectedIndex: _selected,
    onSelected: (i) => context.go(_items[i].$1),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _AccountGate(child: child),
        ),
      ),
    ),
  );
}

final _pushRegistration = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(pushRegistrarProvider).register(),
);

/// Shows the screens once the person has a patient account; otherwise asks for
/// the few details needed to create one. Signing up never links a clinic.
class _AccountGate extends ConsumerWidget {
  const _AccountGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/profile');
    return ref
        .watch(mapProvider(q))
        .when(
          loading: () => const EcLoadingIndicator(),
          error: (e, _) {
            if (e is ApiFailure && e.code?.httpStatus == 403) {
              return AccountSetupPage(
                onDone: () => ref.invalidate(mapProvider),
              );
            }
            return EcErrorState(
              title: 'Could not load your account',
              message: e is ApiFailure ? e.displayMessage : 'Please try again.',
              onRetry: () => ref.invalidate(mapProvider(q)),
            );
          },
          data: (_) {
            // registers this device for push when a token source exists
            ref.watch(_pushRegistration);
            return child;
          },
        );
  }
}

class AccountSetupPage extends ConsumerStatefulWidget {
  const AccountSetupPage({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  ConsumerState<AccountSetupPage> createState() => _AccountSetupState();
}

class _AccountSetupState extends ConsumerState<AccountSetupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(portalRepositoryProvider)
          .send('POST', '/patient-accounts', {
            'displayName': _name.text.trim(),
            if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
            if (_dob.text.trim().isNotEmpty) 'dateOfBirth': _dob.text.trim(),
          });
      widget.onDone();
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = failureText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(EcSpacing.lg),
    children: [
      const PageHeader(
        title: 'Set up your profile',
        subtitle:
            'This creates your personal EazyClinic account. It does not give any clinic access to your records.',
      ),
      Form(
        key: _form,
        child: Column(
          children: [
            EcTextField(
              label: 'Full name',
              controller: _name,
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Enter your full name.' : null,
            ),
            const SizedBox(height: EcSpacing.md),
            EcTextField(
              label: 'Mobile number (optional)',
              controller: _phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: EcSpacing.md),
            EcTextField(
              label: 'Date of birth (YYYY-MM-DD, optional)',
              controller: _dob,
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)
                    ? null
                    : 'Use the format YYYY-MM-DD.';
              },
            ),
          ],
        ),
      ),
      if (_error != null)
        EcInlineMessage(tone: EcStatusTone.error, message: _error!),
      const SizedBox(height: EcSpacing.lg),
      sized(
        EcPrimaryButton(
          label: 'Create my profile',
          onPressed: _busy ? null : _submit,
        ),
        240,
      ),
    ],
  );
}
