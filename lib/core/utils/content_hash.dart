import 'dart:convert';

import 'package:crypto/crypto.dart';

String computeContentHash(String content) {
  return sha256.convert(utf8.encode(content)).toString();
}
