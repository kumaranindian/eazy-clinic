import '../billing_math.dart';

/// Phase 15: effective-dated tax policies.
///
/// A policy describes *how* a country's indirect tax is configured (components,
/// rate periods, exemptions, rounding). It contains **no rates of its own**:
/// rates, thresholds and exemptions must be entered and verified by a
/// qualified local tax specialist before a policy can be used. A policy that
/// is not verified, retired, or without a rate in force on the invoice date
/// cannot produce a tax rule: the invoice fails instead of guessing.
const List<String> taxSupplies = ['any', 'intra', 'inter'];
const List<String> taxTreatments = ['exempt', 'zero_rated'];

final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _key = RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$');

bool isPolicyKey(String? k) => k != null && _key.hasMatch(k);
bool isIsoDate(String? d) {
  if (d == null || !_date.hasMatch(d)) return false;
  final p = DateTime.tryParse(d);
  if (p == null) return false;
  // reject overflow such as 2026-02-31 or 2020-13-45 that Dart normalises
  return '${p.year.toString().padLeft(4, '0')}-'
          '${p.month.toString().padLeft(2, '0')}-'
          '${p.day.toString().padLeft(2, '0')}' ==
      d;
}

/// Why a policy cannot be used for an invoice.
class TaxPolicyUnavailable implements Exception {
  const TaxPolicyUnavailable(this.reason, this.message);

  /// `not_found`, `retired`, `unverified`, `wrong_country`, `no_rate`,
  /// `unknown_exemption`, `no_components`.
  final String reason;
  final String message;

  @override
  String toString() => 'TaxPolicyUnavailable($reason)';
}

/// A tax rule produced from a policy, with what the invoice must remember.
class PolicyTaxRule extends TaxRule {
  const PolicyTaxRule({
    required super.id,
    required super.name,
    required super.components,
    required super.inclusive,
    required this.policyKey,
    required this.policyVersion,
    required this.effectiveOn,
    required this.treatment,
    required this.supply,
    required this.rounding,
    required this.taxType,
  });

  final String policyKey;
  final int policyVersion;

  /// The invoice date the rates were resolved for.
  final String effectiveOn;

  /// `standard`, `exempt` or `zero_rated`.
  final String treatment;
  final String supply;
  final Rounding rounding;
  final String taxType;
}

/// Validates a full policy document. Returns problems as `(field, message)`.
List<(String, String)> validatePolicy(Map<String, Object?> p) {
  final out = <(String, String)>[];
  void bad(String f, String m) => out.add((f, m));
  if (!isPolicyKey(p['key'] as String?)) {
    bad('key', 'key must be lower-case letters, digits and hyphens.');
  }
  final title = p['title'];
  if (title is! String || title.trim().length < 3 || title.length > 120) {
    bad('title', 'title is required.');
  }
  final cc = p['countryCode'];
  if (cc is! String || !RegExp(r'^[A-Z]{2}$').hasMatch(cc)) {
    bad('countryCode', 'countryCode must be an ISO 3166-1 alpha-2 code.');
  }
  final tt = p['taxType'];
  if (tt is! String || !RegExp(r'^[A-Za-z][A-Za-z0-9 ]{1,19}$').hasMatch(tt)) {
    bad('taxType', 'taxType is required (for example GST or VAT).');
  }
  if (p['mode'] != 'inclusive' && p['mode'] != 'exclusive') {
    bad('mode', 'mode must be inclusive or exclusive.');
  }
  if (Rounding.tryParse(p['rounding']) == null) {
    bad('rounding', 'rounding must be half_up, half_even or down.');
  }
  if (!taxSupplies.contains(p['defaultSupply'])) {
    bad('defaultSupply', 'defaultSupply must be any, intra or inter.');
  }
  if (p['status'] != 'published' && p['status'] != 'retired') {
    bad('status', 'status must be published or retired.');
  }
  final comps = p['components'];
  if (comps is! List || comps.isEmpty || comps.length > 8) {
    bad('components', 'Provide 1-8 components.');
  } else {
    final names = <String>{};
    for (var i = 0; i < comps.length; i++) {
      final c = comps[i];
      final f = 'components[$i]';
      if (c is! Map) {
        bad(f, 'must be an object.');
        continue;
      }
      final n = c['name'];
      if (n is! String ||
          !RegExp(r'^[A-Za-z][A-Za-z0-9 ]{0,19}$').hasMatch(n)) {
        bad('$f.name', 'name is required (up to 20 characters).');
      } else if (!names.add('$n/${c['supply']}')) {
        bad('$f.name', 'duplicate component "$n" for the same supply.');
      }
      if (!taxSupplies.contains(c['supply'])) {
        bad('$f.supply', 'supply must be any, intra or inter.');
      }
      final rates = c['rates'];
      if (rates is! List || rates.length > 40) {
        bad('$f.rates', 'rates must be a list of rate periods.');
        continue;
      }
      final periods = <(String, String?)>[];
      for (var j = 0; j < rates.length; j++) {
        final r = rates[j];
        final g = '$f.rates[$j]';
        if (r is! Map) {
          bad(g, 'must be an object.');
          continue;
        }
        final from = r['effectiveFrom'] as String?;
        final to = r['effectiveTo'] as String?;
        final bps = r['rateBps'];
        if (!isIsoDate(from)) {
          bad('$g.effectiveFrom', 'effectiveFrom must be YYYY-MM-DD.');
        }
        if (to != null && !isIsoDate(to)) {
          bad('$g.effectiveTo', 'effectiveTo must be YYYY-MM-DD.');
        }
        if (from != null && to != null && to.compareTo(from) < 0) {
          bad(
            '$g.effectiveTo',
            'effectiveTo must not be before effectiveFrom.',
          );
        }
        if (bps is! int || bps < 0 || bps > 10000) {
          bad(
            '$g.rateBps',
            'rateBps must be a whole number of basis points, 0-10000.',
          );
        }
        if (isIsoDate(from)) periods.add((from!, isIsoDate(to) ? to : null));
      }
      periods.sort((a, b) => a.$1.compareTo(b.$1));
      for (var k = 1; k < periods.length; k++) {
        final prevEnd = periods[k - 1].$2;
        if (prevEnd == null || prevEnd.compareTo(periods[k].$1) >= 0) {
          bad('$f.rates', 'Rate periods must not overlap.');
          break;
        }
      }
    }
  }
  final ex = p['exemptions'];
  if (ex is! List || ex.length > 20) {
    bad('exemptions', 'exemptions must be a list.');
  } else {
    final keys = <String>{};
    for (var i = 0; i < ex.length; i++) {
      final e = ex[i];
      final f = 'exemptions[$i]';
      if (e is! Map) {
        bad(f, 'must be an object.');
        continue;
      }
      if (!isPolicyKey(e['key'] as String?) || !keys.add('${e['key']}')) {
        bad(
          '$f.key',
          'key must be unique lower-case letters, digits and hyphens.',
        );
      }
      if ('${e['label'] ?? ''}'.trim().length < 3) {
        bad('$f.label', 'label is required.');
      }
      if (!taxTreatments.contains(e['treatment'])) {
        bad('$f.treatment', 'treatment must be exempt or zero_rated.');
      }
    }
  }
  final src = p['source'];
  if (src is! Map || '${src['reference'] ?? ''}'.trim().isEmpty) {
    bad('source', 'source.reference is required.');
  }
  return out;
}

/// True when at least one component has a rate period.
bool hasAnyRate(Map<String, Object?> p) => [
  for (final c in (p['components'] as List? ?? const []))
    ...((c as Map)['rates'] as List? ?? const []),
].isNotEmpty;

/// The rate (basis points) of [component] on [date], or null.
int? rateOn(Map<String, Object?> component, String date) {
  for (final r in (component['rates'] as List? ?? const [])) {
    final m = (r as Map).cast<String, Object?>();
    final from = m['effectiveFrom']! as String;
    final to = m['effectiveTo'] as String?;
    if (from.compareTo(date) <= 0 && (to == null || date.compareTo(to) <= 0)) {
      return m['rateBps']! as int;
    }
  }
  return null;
}

/// Builds the tax rule a [policy] prescribes on [date] (`YYYY-MM-DD`, the
/// invoice date in the clinic's time zone) for a clinic in [countryCode].
///
/// Throws [TaxPolicyUnavailable] instead of guessing: unverified, retired,
/// wrong country, unknown exemption, a component with no rate in force.
PolicyTaxRule resolvePolicyRule(
  Map<String, Object?>? policy, {
  required String countryCode,
  required String date,
  String? exemptionKey,
  String? supply,
}) {
  if (policy == null) {
    throw const TaxPolicyUnavailable(
      'not_found',
      'That tax policy does not exist.',
    );
  }
  final key = '${policy['key']}';
  if (policy['status'] != 'published') {
    throw const TaxPolicyUnavailable('retired', 'That tax policy is retired.');
  }
  if ((policy['verification'] as Map?)?['status'] != 'verified') {
    throw const TaxPolicyUnavailable(
      'unverified',
      'That tax policy has not been verified by a tax specialist yet.',
    );
  }
  if (policy['countryCode'] != countryCode) {
    throw const TaxPolicyUnavailable(
      'wrong_country',
      'That tax policy belongs to a different country than the clinic.',
    );
  }
  final mode = Rounding.tryParse(policy['rounding']) ?? Rounding.halfUp;
  final inclusive = policy['mode'] == 'inclusive';
  final effectiveSupply = supply ?? '${policy['defaultSupply']}';
  Map<String, Object?>? exemption;
  if (exemptionKey != null) {
    exemption = [
      for (final e in (policy['exemptions'] as List? ?? const []))
        (e as Map).cast<String, Object?>(),
    ].where((e) => e['key'] == exemptionKey).firstOrNull;
    if (exemption == null) {
      throw const TaxPolicyUnavailable(
        'unknown_exemption',
        'That exemption is not defined in the tax policy.',
      );
    }
  }
  final treatment = exemption == null
      ? 'standard'
      : '${exemption['treatment']}';
  final comps = <TaxComponent>[];
  if (treatment != 'exempt') {
    final applicable = [
      for (final c
          in (policy['components']! as List).cast<Map<String, Object?>>())
        if (c['supply'] == 'any' || c['supply'] == effectiveSupply) c,
    ];
    if (applicable.isEmpty) {
      throw const TaxPolicyUnavailable(
        'no_components',
        'The tax policy has no component for this kind of supply.',
      );
    }
    for (final c in applicable) {
      final bps = rateOn(c, date);
      if (bps == null) {
        throw TaxPolicyUnavailable(
          'no_rate',
          'The tax policy has no ${c['name']} rate in force on $date.',
        );
      }
      comps.add(
        TaxComponent('${c['name']}', treatment == 'zero_rated' ? 0 : bps),
      );
    }
  }
  return PolicyTaxRule(
    id: 'policy:$key${exemptionKey == null ? '' : ':$exemptionKey'}',
    name: '${policy['title']}',
    components: comps,
    inclusive: inclusive,
    policyKey: key,
    policyVersion: policy['version']! as int,
    effectiveOn: date,
    treatment: treatment,
    supply: effectiveSupply,
    rounding: mode,
    taxType: '${policy['taxType']}',
  );
}
