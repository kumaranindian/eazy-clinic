import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Delivery channels. In-app is the core channel; push uses FCM; email, SMS
/// and WhatsApp are adapters that stay `configuration_required` until a
/// provider is configured for the environment.
const List<String> notificationChannels = [
  'in_app',
  'push',
  'email',
  'sms',
  'whatsapp',
];

/// Channels a clinic may switch on besides the defaults.
const Set<String> defaultChannels = {'in_app', 'push'};

/// Transactional service messages: the in-app entry cannot be opted out of.
const Set<String> essentialCategories = {
  'appointment_booked',
  'appointment_confirmed',
  'appointment_rescheduled',
  'appointment_cancelled',
  'appointment_reminder',
  'token_generated',
  'doctor_calling',
  'queue_changed',
  'summary_available',
  'prescription_available',
  'report_available',
  'followup_reminder',
  'invoice_generated',
  'payment_received',
  'refund_status',
  'lab_sample_rejected',
  'security_event',
  // Phase 14: a credential or compliance approval is expiring or expired.
  'compliance_expiry',
};

/// Promotional or informational messages need an explicit opt-in.
const Set<String> promotionalCategories = {'clinic_announcement'};

const List<String> deliveryStatuses = [
  'queued',
  'processing',
  'sent',
  'delivered',
  'retry_scheduled',
  'cancelled',
  'permanently_failed',
  'configuration_required',
];

const int maxDeliveryAttempts = 5;

/// Variables a template for an event type may use. Nothing clinical is on the
/// list, so a template cannot leak a diagnosis, medicine or lab value.
const Map<String, Set<String>> eventVariables = {
  'appointment_reminder': {'clinicName', 'doctorName', 'date', 'time'},
  'followup_reminder': {'clinicName', 'date'},
  'report_available': {'clinicName'},
  'lab_sample_rejected': {'clinicName'},
  'security_event': {'clinicName'},
};
const Set<String> defaultVariables = {'clinicName'};

Set<String> variablesFor(String eventType) =>
    eventVariables[eventType] ?? defaultVariables;

/// A message definition for one event type, channel and locale.
class TemplateDef {
  const TemplateDef({
    required this.eventType,
    required this.channel,
    required this.locale,
    required this.subject,
    required this.body,
    this.version = 1,
  });

  final String eventType;
  final String channel;
  final String locale;
  final String subject;
  final String body;
  final int version;
}

/// Built-in templates (version 1). Sensitive events stay generic: details are
/// read in the app after authentication.
const List<TemplateDef> builtinTemplates = [
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'in_app',
    locale: 'en',
    subject: 'Appointment reminder',
    body: 'You have an appointment at {{clinicName}} on {{date}} at {{time}}.',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'push',
    locale: 'en',
    subject: 'Appointment reminder',
    body: 'You have an upcoming appointment. Open the app for details.',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'email',
    locale: 'en',
    subject: 'Appointment reminder from {{clinicName}}',
    body:
        'You have an appointment on {{date}} at {{time}} with {{doctorName}}.',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'sms',
    locale: 'en',
    subject: '',
    body: '{{clinicName}}: appointment on {{date}} at {{time}}.',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'in_app',
    locale: 'en',
    subject: 'Follow-up reminder',
    body: 'A follow-up visit with {{clinicName}} is recommended on {{date}}.',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'push',
    locale: 'en',
    subject: 'Follow-up reminder',
    body: 'You have a follow-up visit coming up. Open the app for details.',
  ),
  // Phase 13: starter translations (machine-assisted, not reviewed by a
  // native speaker; generic wording only, no clinical detail). Placeholders
  // must match the English template exactly (enforced by a test).
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'in_app',
    locale: 'ar',
    subject: 'تذكير بالموعد',
    body: 'لديك موعد في {{clinicName}} بتاريخ {{date}} الساعة {{time}}.',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'push',
    locale: 'ar',
    subject: 'تذكير بالموعد',
    body: 'لديك موعد قريب. افتح التطبيق لمعرفة التفاصيل.',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'in_app',
    locale: 'hi',
    subject: 'अपॉइंटमेंट अनुस्मारक',
    body: '{{clinicName}} में {{date}} को {{time}} बजे आपका अपॉइंटमेंट है।',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'push',
    locale: 'hi',
    subject: 'अपॉइंटमेंट अनुस्मारक',
    body: 'आपका अपॉइंटमेंट जल्द है। विवरण के लिए ऐप खोलें।',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'in_app',
    locale: 'ta',
    subject: 'சந்திப்பு நினைவூட்டல்',
    body:
        '{{clinicName}} இல் {{date}} அன்று {{time}} மணிக்கு உங்களுக்கு சந்திப்பு உள்ளது.',
  ),
  TemplateDef(
    eventType: 'appointment_reminder',
    channel: 'push',
    locale: 'ta',
    subject: 'சந்திப்பு நினைவூட்டல்',
    body:
        'உங்கள் சந்திப்பு விரைவில் உள்ளது. விவரங்களுக்கு செயலியைத் திறக்கவும்.',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'in_app',
    locale: 'ar',
    subject: 'تذكير بالمتابعة',
    body: 'يُوصى بزيارة متابعة مع {{clinicName}} بتاريخ {{date}}.',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'push',
    locale: 'ar',
    subject: 'تذكير بالمتابعة',
    body: 'لديك زيارة متابعة قريبة. افتح التطبيق لمعرفة التفاصيل.',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'in_app',
    locale: 'hi',
    subject: 'फ़ॉलो-अप अनुस्मारक',
    body: '{{clinicName}} के साथ {{date}} को फ़ॉलो-अप विज़िट की सलाह दी गई है।',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'push',
    locale: 'hi',
    subject: 'फ़ॉलो-अप अनुस्मारक',
    body: 'आपकी फ़ॉलो-अप विज़िट जल्द है। विवरण के लिए ऐप खोलें।',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'in_app',
    locale: 'ta',
    subject: 'தொடர் சிகிச்சை நினைவூட்டல்',
    body:
        '{{clinicName}} உடன் {{date}} அன்று தொடர் சந்திப்பு பரிந்துரைக்கப்படுகிறது.',
  ),
  TemplateDef(
    eventType: 'followup_reminder',
    channel: 'push',
    locale: 'ta',
    subject: 'தொடர் சிகிச்சை நினைவூட்டல்',
    body:
        'உங்கள் தொடர் சந்திப்பு விரைவில் உள்ளது. விவரங்களுக்கு செயலியைத் திறக்கவும்.',
  ),
];

class TemplateException implements Exception {
  const TemplateException(this.message);
  final String message;
  @override
  String toString() => message;
}

final RegExp _placeholder = RegExp(r'\{\{\s*([A-Za-z][A-Za-z0-9_]*)\s*\}\}');

/// Names used by a template text.
Set<String> placeholdersIn(String text) => {
  for (final m in _placeholder.allMatches(text)) m.group(1)!,
};

/// Bidirectional control characters (embeddings, overrides, isolates, marks,
/// Arabic letter mark). Removed from interpolated values so a name or free
/// text can neither reorder the surrounding message nor disguise it.
final RegExp _bidiControls = RegExp(
  r'[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]',
);

String _clean(String v) => v
    .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
    .replaceAll(_bidiControls, '')
    .replaceAll('{{', '')
    .replaceAll('}}', '')
    .trim();

String escapeHtml(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Replaces `{{name}}` placeholders in a single pass (no logic, no recursion,
/// no expressions, so there is nothing to inject into). Unknown names and
/// missing values are errors; values are cleaned and, for HTML, escaped.
///
/// With [rtl] (right-to-left languages) every value is wrapped in a Unicode
/// first-strong isolate (U+2068 ... U+2069), so Latin identifiers, numbers,
/// phone numbers and names keep their own direction inside Arabic text.
String renderTemplate(
  String text,
  Map<String, String> values, {
  required Set<String> allowed,
  bool html = false,
  bool rtl = false,
}) {
  return text.replaceAllMapped(_placeholder, (m) {
    final name = m.group(1)!;
    if (!allowed.contains(name)) {
      throw TemplateException('Variable $name is not allowed here.');
    }
    final v = values[name];
    if (v == null || v.trim().isEmpty) {
      throw TemplateException('Variable $name has no value.');
    }
    final c = _clean(v);
    final out = html ? escapeHtml(c) : c;
    return rtl ? '\u2068$out\u2069' : out;
  });
}

/// Delay before attempt number [attempt] (1-based count of failures so far):
/// 30 s doubling up to 30 min, with +/-20% jitter.
Duration backoff(int attempt, Random rng) {
  final base = min(30 * pow(2, max(0, attempt - 1)).toInt(), 1800);
  final jitter = 0.8 + rng.nextDouble() * 0.4;
  return Duration(milliseconds: (base * 1000 * jitter).round());
}

// ----------------------------------------------------------------- providers

/// Outcome of handing a message to a provider. `accepted` is **not** proof of
/// delivery.
class ProviderResult {
  const ProviderResult(this.outcome, {this.messageId, this.error});

  /// `accepted`, `invalid_token`, `transient`, `permanent`, `not_configured`.
  final String outcome;
  final String? messageId;

  /// Already sanitized: never a raw provider body.
  final String? error;
}

abstract interface class FcmSender {
  bool get configured;
  Future<ProviderResult> send({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  });
}

class UnconfiguredFcmSender implements FcmSender {
  const UnconfiguredFcmSender();
  @override
  bool get configured => false;
  @override
  Future<ProviderResult> send({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async => const ProviderResult('not_configured');
}

/// FCM HTTP v1 sender. [client] must carry Google credentials with the
/// `firebase.messaging` scope. Not exercised against live FCM in this
/// repository (needs a configured Firebase project and a device token).
class HttpFcmSender implements FcmSender {
  HttpFcmSender({
    required this.projectId,
    required http.Client client,
    this.host = 'https://fcm.googleapis.com',
  }) : _client = client;

  final String projectId;
  final String host;
  final http.Client _client;

  @override
  bool get configured => true;

  @override
  Future<ProviderResult> send({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    final http.Response r;
    try {
      r = await _client.post(
        Uri.parse('$host/v1/projects/$projectId/messages:send'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': token,
            'notification': {'title': title, 'body': body},
            'data': data,
            'android': {'priority': 'high'},
          },
        }),
      );
    } on Object {
      return const ProviderResult('transient', error: 'network_error');
    }
    if (r.statusCode == 200) {
      String? name;
      try {
        name = (jsonDecode(r.body) as Map)['name'] as String?;
      } on Object {
        name = null;
      }
      return ProviderResult('accepted', messageId: name);
    }
    if (r.statusCode == 404 || r.statusCode == 410) {
      return const ProviderResult('invalid_token', error: 'token_unregistered');
    }
    if (r.statusCode == 429 || r.statusCode >= 500) {
      return ProviderResult('transient', error: 'http_${r.statusCode}');
    }
    if (r.statusCode == 400 && r.body.contains('INVALID_ARGUMENT')) {
      return const ProviderResult('invalid_token', error: 'invalid_argument');
    }
    return ProviderResult('permanent', error: 'http_${r.statusCode}');
  }
}

/// Email, SMS or WhatsApp provider. Production wiring has none: the delivery
/// is recorded as `configuration_required` instead of pretending to send.
abstract interface class MessageProvider {
  bool get configured;
  Future<ProviderResult> send({
    required String address,
    required String subject,
    required String body,
  });
}
