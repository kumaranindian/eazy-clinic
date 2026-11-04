import 'package:backend/features/notifications/notification_core.dart';

/// Records every FCM call and answers with a scripted outcome (tests only).
class MockFcm implements FcmSender {
  MockFcm({this.configuredFlag = true});

  final bool configuredFlag;
  final List<({String token, String title, String body})> sent = [];

  /// Outcome per call, repeated from the last entry; default accepted.
  List<ProviderResult> script = [];
  int _i = 0;

  @override
  bool get configured => configuredFlag;

  @override
  Future<ProviderResult> send({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    sent.add((token: token, title: title, body: body));
    if (script.isEmpty) {
      return ProviderResult('accepted', messageId: 'm${sent.length}');
    }
    final r = script[_i < script.length ? _i : script.length - 1];
    _i++;
    return r;
  }
}

class MockProvider implements MessageProvider {
  MockProvider({this.configured = true});

  @override
  final bool configured;
  final List<({String address, String subject, String body})> sent = [];

  @override
  Future<ProviderResult> send({
    required String address,
    required String subject,
    required String body,
  }) async {
    sent.add((address: address, subject: subject, body: body));
    return const ProviderResult('accepted', messageId: 'p1');
  }
}
