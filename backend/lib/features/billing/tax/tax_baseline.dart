/// Baseline tax policy *shells* for India (GST) and the UAE (VAT).
///
/// **They contain no rates.** Every rate, threshold, exemption and invoice
/// requirement must be entered, and the policy verified, by a qualified local
/// tax specialist before any clinic can use it (an unverified policy, or one
/// with no rate in force on the invoice date, makes tax calculation fail
/// instead of guessing). Source links are the authorities' public home pages;
/// they were **not** fetched or verified when this was drafted (2026-11-05).
List<Map<String, Object?>> baselineTaxPolicies() => [
  _shell(
    key: 'in-gst',
    title: 'India GST (shell - rates to be entered by a tax specialist)',
    countryCode: 'IN',
    taxType: 'GST',
    components: [
      _component('CGST', 'intra'),
      _component('SGST', 'intra'),
      _component('IGST', 'inter'),
    ],
    defaultSupply: 'intra',
    source: 'https://www.gst.gov.in',
    note:
        'Intra-state supplies split into CGST and SGST; inter-state supplies '
        'use IGST. Health-care exemptions and thresholds must be defined by a '
        'tax specialist. No GST filing, e-way bill or e-invoice IRN is performed.',
  ),
  _shell(
    key: 'ae-vat',
    title: 'UAE VAT (shell - rates to be entered by a tax specialist)',
    countryCode: 'AE',
    taxType: 'VAT',
    components: [_component('VAT', 'any')],
    defaultSupply: 'any',
    source: 'https://tax.gov.ae',
    note:
        'Whether a clinic is registered, and which health-care supplies are '
        'exempt or zero-rated, must be determined by a tax specialist. No FTA '
        'filing or e-invoicing is performed.',
  ),
];

Map<String, Object?> _component(String name, String supply) => {
  'name': name,
  'supply': supply,
  'rates': <Object?>[],
};

Map<String, Object?> _shell({
  required String key,
  required String title,
  required String countryCode,
  required String taxType,
  required List<Map<String, Object?>> components,
  required String defaultSupply,
  required String source,
  required String note,
}) => {
  'key': key,
  'title': title,
  'countryCode': countryCode,
  'taxType': taxType,
  'mode': 'exclusive',
  'rounding': 'half_up',
  'defaultSupply': defaultSupply,
  'status': 'published',
  'components': components,
  'exemptions': <Object?>[],
  'invoiceRequirements': <Object?>[],
  'source': {
    'reference': source,
    'note': note,
    'fetched': false,
    'draftedOn': '2026-11-05',
  },
  'verification': {
    'status': 'unverified',
    'by': null,
    'at': null,
    'reviewerNote': null,
  },
};
