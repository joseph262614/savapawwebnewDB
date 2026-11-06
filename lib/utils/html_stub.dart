import 'dart:typed_data';

class PickedImageFile {
  final Uint8List bytes;
  final String name;

  PickedImageFile({required this.bytes, required this.name});
}

Future<PickedImageFile?> pickImageWeb({int maxDimension = 1080, double quality = 0.75}) async {
  return null;
}

void openUrl(String url) {}
