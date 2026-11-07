// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

class PickedImageFile {
  final Uint8List bytes;
  final String name;

  PickedImageFile({required this.bytes, required this.name});
}

Future<PickedImageFile?> pickImageWeb({int maxDimension = 1080, double quality = 0.75}) async {
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
        final objectUrl = html.Url.createObjectUrlFromBlob(file);
        final img = html.ImageElement();

        img.onLoad.listen((_) {
          try {
            int width = img.naturalWidth > 0 ? img.naturalWidth : (img.width ?? 800);
            int height = img.naturalHeight > 0 ? img.naturalHeight : (img.height ?? 800);

            if (width > maxDimension || height > maxDimension) {
              if (width > height) {
                height = (height * (maxDimension / width)).round();
                width = maxDimension;
              } else {
                width = (width * (maxDimension / height)).round();
                height = maxDimension;
              }
            }

            final canvas = html.CanvasElement(width: width, height: height);
            final ctx = canvas.context2D;
            ctx.drawImageScaled(img, 0, 0, width, height);

            final dataUrl = canvas.toDataUrl('image/jpeg', quality);
            html.Url.revokeObjectUrl(objectUrl);

            final commaIdx = dataUrl.indexOf(',');
            final base64Str = commaIdx != -1 ? dataUrl.substring(commaIdx + 1) : dataUrl;
            final bytes = base64Decode(base64Str);

            cleanup();
            if (!completer.isCompleted) {
              completer.complete(PickedImageFile(bytes: bytes, name: file.name));
            }
          } catch (e) {
            // Fallback to raw reader if canvas processing encounters any error
            html.Url.revokeObjectUrl(objectUrl);
            _readRawFile(file, cleanup, completer);
          }
        });

        img.onError.listen((_) {
          html.Url.revokeObjectUrl(objectUrl);
          _readRawFile(file, cleanup, completer);
        });

        img.src = objectUrl;
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

void _readRawFile(html.File file, void Function() cleanup, Completer<PickedImageFile?> completer) {
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
}

void openUrl(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}

Widget buildWebCorsFreeImage({
  required String url,
  required BoxFit fit,
  double? width,
  double? height,
  required Widget fallback,
}) {
  return _WebCorsFreeImage(
    key: ValueKey<String>(url),
    url: url,
    fit: fit,
    width: width,
    height: height,
    fallback: fallback,
  );
}

class _WebCorsFreeImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget fallback;

  const _WebCorsFreeImage({
    super.key,
    required this.url,
    required this.fit,
    this.width,
    this.height,
    required this.fallback,
  });

  @override
  State<_WebCorsFreeImage> createState() => _WebCorsFreeImageState();
}

class _WebCorsFreeImageState extends State<_WebCorsFreeImage> {
  bool _hasError = false;

  String _boxFitToCss(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitWidth:
      case BoxFit.fitHeight:
      case BoxFit.scaleDown:
        return 'scale-down';
      case BoxFit.none:
        return 'none';
      case BoxFit.cover:
        return 'cover';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedWidth = widget.width ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : 400.0);
        final resolvedHeight = widget.height ??
            (constraints.hasBoundedHeight ? constraints.maxHeight : 260.0);

        return SizedBox(
          width: resolvedWidth,
          height: resolvedHeight,
          child: HtmlElementView.fromTagName(
            tagName: 'img',
            onElementCreated: (Object element) {
              final img = element as html.ImageElement;
              img.referrerPolicy = 'no-referrer';
              img.src = widget.url;
              img.style.width = '100%';
              img.style.height = '100%';
              img.style.objectFit = _boxFitToCss(widget.fit);
              img.style.display = 'block';
              img.style.border = 'none';
              img.onError.listen((_) {
                if (mounted) {
                  setState(() => _hasError = true);
                }
              });
            },
          ),
        );
      },
    );
  }
}
