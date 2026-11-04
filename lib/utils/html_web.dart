// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

class PickedImageFile {
  final Uint8List bytes;
  final String name;

  PickedImageFile({required this.bytes, required this.name});
}

Future<PickedImageFile?> pickImageWeb() async {
  final completer = Completer<PickedImageFile?>();
  try {
    final uploadInput = html.FileUploadInputElement()
      ..accept = 'image/png,image/jpeg,image/jpg,image/webp'
      ..style.display = 'none';

    html.document.body?.children.add(uploadInput);

    void cleanup() {
      try {
        uploadInput.remove();
      } catch (_) {}
    }

    uploadInput.onChange.listen((event) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();

        reader.onLoadEnd.listen((e) {
          cleanup();
          if (reader.result != null) {
            final Uint8List bytes = Uint8List.fromList(reader.result as List<int>);
            if (!completer.isCompleted) {
              completer.complete(PickedImageFile(bytes: bytes, name: file.name));
            }
          } else {
            if (!completer.isCompleted) completer.complete(null);
          }
        });

        reader.onError.listen((e) {
          cleanup();
          if (!completer.isCompleted) completer.complete(null);
        });

        reader.readAsArrayBuffer(file);
      } else {
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      }
    });

    uploadInput.addEventListener('cancel', (e) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    });

    uploadInput.click();
  } catch (e) {
    if (!completer.isCompleted) completer.complete(null);
  }
  return completer.future;
}

void openUrl(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}
