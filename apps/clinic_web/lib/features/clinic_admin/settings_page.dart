import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../control_plane/data/control_plane_repository.dart';
import '../shared/async_body.dart';
import '../shared/ui_kit.dart';
import 'form_kit.dart';
import 'providers.dart';

const _zones = [
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Singapore',
  'Asia/Dhaka',
  'Asia/Colombo',
  'Asia/Kathmandu',
  'Europe/London',
  'America/New_York',
  'Australia/Sydney',
  'UTC',
];
const _languages = {
  'en': 'English',
  'hi': 'Hindi',
  'mr': 'Marathi',
  'ta': 'Tamil',
  'te': 'Telugu',
  'bn': 'Bengali',
  'gu': 'Gujarati',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'pa': 'Punjabi',
};

/// Regional settings, default durations, weekly operating hours, holidays and
/// special working days. The time zone is stored explicitly (no default).
class ClinicSettingsPage extends ConsumerStatefulWidget {
  const ClinicSettingsPage({super.key});

  @override
  ConsumerState<ClinicSettingsPage> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<ClinicSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _f = FormFields(['appt', 'consult']);
  String? _zone;
  String _language = 'en';
  bool _regRequired = true;
  Map<String, Object?> _weekly = {};
  List<Map<String, Object?>> _holidays = [];
  List<Map<String, Object?>> _special = [];
  Map<String, Object?>? _initialWeekly;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  String? _ok;

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _fill(Json s) {
    _zone = s['timezone'] as String?;
    _language = (s['language'] as String?) ?? 'en';
    _regRequired = s['doctorRegistrationRequired'] != false;
    _f
      ..set('appt', s['appointmentDurationMinutes'])
      ..set('consult', s['consultationDurationMinutes']);
    _initialWeekly = (s['weeklyHours'] as Map?)?.cast<String, Object?>();
    _weekly = {...?_initialWeekly};
    _holidays = [
      for (final h
          in ((s['holidays'] as List?) ?? const [])
              .cast<Map<String, Object?>>())
        {...h},
    ];
    _special = [
      for (final h
          in ((s['specialDays'] as List?) ?? const [])
              .cast<Map<String, Object?>>())
        {...h},
    ];
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_zone == null) {
      setState(() => _error = 'Choose the clinic time zone.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });
    try {
      await ref
          .read(controlPlaneRepositoryProvider)
          .sendMap('PATCH', '/clinics/current/settings', {
            'timezone': _zone,
            'currency': 'INR',
            'language': _language,
            'appointmentDurationMinutes': int.parse(_f.text('appt')),
            'consultationDurationMinutes': int.parse(_f.text('consult')),
            'doctorRegistrationRequired': _regRequired,
            'weeklyHours': _weekly,
            'holidays': _holidays,
            'specialDays': _special,
          });
      ref.invalidate(clinicSettingsProvider);
      if (mounted) {
        setState(() {
          _saving = false;
          _ok = 'Settings saved.';
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureText(e);
        });
      }
    }
  }

  Future<void> _addDate({required bool special}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    final date = fmtDate(d);
    setState(() {
      if (special) {
        _special = [
          ..._special,
          {
            'date': date,
            'open': true,
            'from': '10:00',
            'to': '13:00',
            'breaks': <Object?>[],
          },
        ];
      } else {
        _holidays = [
          ..._holidays,
          {'date': date, 'name': ''},
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = can(ref, ClinicPermission.clinicSettingsManage);
    if (!_loaded) {
      return AsyncBody(
        value: ref.watch(clinicSettingsProvider),
        onRetry: () => ref.invalidate(clinicSettingsProvider),
        builder: (s) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _fill(s));
          });
          return const EcLoadingIndicator();
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.all(EcSpacing.lg),
      children: [
        PageHeader(
          title: 'Clinic settings',
          subtitle: canEdit
              ? 'Regional settings and operating hours. Branches can override the hours.'
              : 'You can view these settings; only clinic owners and admins can change them.',
        ),
        if (_zone == null)
          const Padding(
            padding: EdgeInsets.only(bottom: EcSpacing.lg),
            child: EcInlineMessage(
              tone: EcStatusTone.warning,
              message: 'Choose your clinic time zone. It is never assumed.',
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.lg),
            child: EcInlineMessage(message: _error!),
          ),
        if (_ok != null)
          Padding(
            padding: const EdgeInsets.only(bottom: EcSpacing.lg),
            child: EcInlineMessage(message: _ok!, tone: EcStatusTone.success),
          ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Section(
                title: 'Regional',
                child: Wrap(
                  spacing: EcSpacing.lg,
                  runSpacing: EcSpacing.lg,
                  children: [
                    SizedBox(
                      width: 300,
                      child: EcDropdown<String>(
                        label: 'Time zone',
                        items: [
                          ..._zones,
                          if (_zone != null && !_zones.contains(_zone)) _zone!,
                        ],
                        value: _zone,
                        onChanged: canEdit
                            ? (v) => setState(() => _zone = v)
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: EcTextField(
                        label: 'Currency',
                        enabled: false,
                        hint:
                            '${RegionalDisplay.currency} (${RegionalDisplay.currencyLabel()})',
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: EcDropdown<String>(
                        label: 'Language',
                        items: _languages.keys.toList(),
                        value: _language,
                        itemLabel: (k) => _languages[k] ?? k,
                        onChanged: canEdit
                            ? (v) => setState(() => _language = v ?? _language)
                            : null,
                      ),
                    ),
                    TextRow(
                      label: 'Default appointment (minutes)',
                      controller: _f['appt'],
                      enabled: canEdit,
                      validator: (v) => wholeNumber(v, max: 240),
                      width: 220,
                      maxLength: 3,
                    ),
                    TextRow(
                      label: 'Default consultation (minutes)',
                      controller: _f['consult'],
                      enabled: canEdit,
                      validator: (v) => wholeNumber(v, max: 240),
                      width: 220,
                      maxLength: 3,
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Doctor policy',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Require a medical registration number for every doctor',
                  ),
                  value: _regRequired,
                  onChanged: canEdit
                      ? (v) => setState(() => _regRequired = v)
                      : null,
                ),
              ),
              Section(
                title: 'Weekly operating hours',
                child: WeeklyHoursEditor(
                  initial: _initialWeekly,
                  enabled: canEdit,
                  onChanged: (w) => _weekly = w,
                ),
              ),
              Section(
                title: 'Holidays',
                trailing: canEdit
                    ? TextButton.icon(
                        onPressed: () => _addDate(special: false),
                        icon: const Icon(Icons.add),
                        label: const Text('Add holiday'),
                      )
                    : null,
                child: _holidays.isEmpty
                    ? const Text('No holidays.')
                    : Column(
                        children: [
                          for (final h in _holidays)
                            ListTile(
                              dense: true,
                              title: Text('${h['date']}'),
                              subtitle: Text('${h['name'] ?? ''}'),
                              trailing: canEdit
                                  ? IconButton(
                                      tooltip: 'Remove holiday',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => setState(
                                        () => _holidays = _holidays
                                            .where(
                                              (x) => x['date'] != h['date'],
                                            )
                                            .toList(),
                                      ),
                                    )
                                  : null,
                            ),
                        ],
                      ),
              ),
              Section(
                title: 'Special working days',
                trailing: canEdit
                    ? TextButton.icon(
                        onPressed: () => _addDate(special: true),
                        icon: const Icon(Icons.add),
                        label: const Text('Add day'),
                      )
                    : null,
                child: _special.isEmpty
                    ? const Text(
                        'None. Special days are one-off openings, e.g. a Sunday camp (10:00–13:00 by default).',
                      )
                    : Column(
                        children: [
                          for (final h in _special)
                            ListTile(
                              dense: true,
                              title: Text('${h['date']}'),
                              subtitle: Text('${h['from']}–${h['to']}'),
                              trailing: canEdit
                                  ? IconButton(
                                      tooltip: 'Remove special day',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => setState(
                                        () => _special = _special
                                            .where(
                                              (x) => x['date'] != h['date'],
                                            )
                                            .toList(),
                                      ),
                                    )
                                  : null,
                            ),
                        ],
                      ),
              ),
              if (canEdit)
                SizedBox(
                  width: 220,
                  child: EcPrimaryButton(
                    label: 'Save settings',
                    isLoading: _saving,
                    onPressed: _save,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
