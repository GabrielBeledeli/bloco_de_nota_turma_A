import 'dart:math';

String generateId(DateTime moment) {
  final timestamp = moment.microsecondsSinceEpoch.toRadixString(36);
  final suffix = Random.secure().nextInt(1 << 32).toRadixString(36);

  return '$timestamp$suffix';
}

