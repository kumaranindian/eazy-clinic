import 'dart:math';

final Random _secure = Random.secure();
const String _alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Random, unguessable, URL-safe id (default 20 chars, ~119 bits).
String newId({int length = 20}) => String.fromCharCodes(
  List.generate(
    length,
    (_) => _alphabet.codeUnitAt(_secure.nextInt(_alphabet.length)),
  ),
);
