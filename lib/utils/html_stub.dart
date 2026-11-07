import 'dart:typed_data';
import 'package:flutter/material.dart';

class PickedImageFile {
  final Uint8List bytes;
  final String name;

  PickedImageFile({required this.bytes, required this.name});
}

Future<PickedImageFile?> pickImageWeb({int maxDimension = 1080, double quality = 0.75}) async {
  return null;
}

void openUrl(String url) {}

Widget buildWebCorsFreeImage({
  required String url,
  required BoxFit fit,
  double? width,
  double? height,
  required Widget fallback,
}) {
  return fallback;
}
