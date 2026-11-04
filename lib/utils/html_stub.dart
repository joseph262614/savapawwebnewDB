import 'dart:typed_data';

class PickedImageFile {
  final Uint8List bytes;
  final String name;

  PickedImageFile({required this.bytes, required this.name});
}

Future<PickedImageFile?> pickImageWeb() async {
  return null;
}

void openUrl(String url) {}
