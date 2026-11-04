import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/portal_repository.dart';
import 'providers.dart';
import 'ui_kit.dart';

String _flagLabel(Object? f) => switch ('$f') {
  'low' => 'Low',
  'high' => 'High',
  'abnormal' => 'Outside the usual range',
  'critical_low' => 'Very low',
  'critical_high' => 'Very high',
  'critical' => 'Needs attention',
  'unit_mismatch' => 'Unit differs from the reference',
  'not_assessed' => 'No reference range',
  _ => '',
};

/// Verified, published laboratory reports of the selected person. Values and
/// flags are exactly what the laboratory published; the app never interprets
/// them. Unverified results, internal comments and older versions are not
/// available to the patient.
class LabReports extends ConsumerWidget {
  const LabReports({required this.params, super.key});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query('/patient/lab-reports', params);
    return AsyncBody(
      value: ref.watch(listProvider(q)),
      onRetry: () => ref.invalidate(listProvider(q)),
      builder: (reports) {
        if (reports.isEmpty) {
          return const EcEmptyState(
            title: 'No laboratory reports yet',
            message:
                'Reports appear here after the laboratory has checked and published them.',
            icon: Icons.science_outlined,
          );
        }
        return Column(
          children: [
            for (final r in reports) _ReportCard(report: r, params: params),
          ],
        );
      },
    );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({required this.report, required this.params});

  final Json report;
  final Map<String, String> params;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final id = '${r['reportId']}';
    return Section(
      title: '${r['clinicName'] ?? 'Clinic'} · ${r['reportNumber']}',
      trailing: TextButton(
        key: Key('open-report-$id'),
        onPressed: () => setState(() => _open = !_open),
        child: Text(_open ? 'Hide' : 'View'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ((r['tests'] as List?) ?? const []).join(', '),
            style: EcTypography.bodyStrong,
          ),
          Text(
            'Published ${shortDateTime(r['publishedAt'])}',
            style: EcTypography.bodySecondary,
          ),
          if (r['external'] == true)
            Padding(
              padding: const EdgeInsets.only(top: EcSpacing.xs),
              child: EcInlineMessage(
                tone: EcStatusTone.info,
                message: r['verifiedByClinic'] == true
                    ? 'Produced by an outside laboratory and reviewed by your clinic.'
                    : 'Produced by an outside laboratory.',
              ),
            ),
          if (_open) _Detail(report: r, params: widget.params),
        ],
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.report, required this.params});

  final Json report;
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = Query(
      '/patient/clinics/${report['clinicId']}/lab-reports/${report['reportId']}',
      params,
    );
    return AsyncBody(
      value: ref.watch(mapProvider(q)),
      onRetry: () => ref.invalidate(mapProvider(q)),
      builder: (d) {
        final tests = ((d['tests'] as List?) ?? const []).cast<Json>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in tests) ...[
              const SizedBox(height: EcSpacing.md),
              Text('${t['name']}', style: EcTypography.bodyStrong),
              if (t['observations'] == null)
                const Text(
                  'This report is a file from the outside laboratory. Ask your clinic for a copy.',
                ),
              for (final o
                  in ((t['observations'] as List?) ?? const []).cast<Json>())
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${o['name']}: ${o['value']}${o['unit'] == null ? '' : ' ${o['unit']}'}',
                  ),
                  subtitle: o['range'] is Map
                      ? Text(
                          'Reference: ${(o['range'] as Map)['low'] ?? ''} – ${(o['range'] as Map)['high'] ?? ''} ${(o['range'] as Map)['unit'] ?? ''}',
                        )
                      : null,
                  trailing: _flagLabel(o['flag']).isEmpty
                      ? null
                      : Text(
                          _flagLabel(o['flag']),
                          key: Key('flag-${o['name']}'),
                          style: EcTypography.bodyStrong.copyWith(
                            color: '${o['flag']}'.startsWith('critical')
                                ? EcColors.error
                                : EcColors.warning,
                          ),
                        ),
                ),
            ],
            const SizedBox(height: EcSpacing.md),
            Text('${d['disclaimer'] ?? ''}', style: EcTypography.bodySecondary),
          ],
        );
      },
    );
  }
}
