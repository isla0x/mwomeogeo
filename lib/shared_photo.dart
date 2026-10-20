import 'dart:typed_data';

import 'package:image/image.dart' as img;

const maxSharedPhotoBytes = 128 * 1024;

/// Small JPEGs keep the Spark database and transfer quotas usable for a small group.
/// ponytail: photos share the 1 GiB database quota; use object storage at scale.
Uint8List encodeSharedPhoto(Uint8List input) {
  if (input.length < 8) throw const FormatException('지원하지 않는 사진 형식이에요.');
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('지원하지 않는 사진 형식이에요.');
  var photo = img.bakeOrientation(decoded);
  photo.exif.clear();
  for (final edge in [960, 720, 480, 320]) {
    if (photo.width > edge || photo.height > edge) {
      photo = img.copyResize(
        photo,
        width: photo.width >= photo.height ? edge : null,
        height: photo.height > photo.width ? edge : null,
        interpolation: img.Interpolation.average,
      );
    }
    final encoded = img.encodeJpg(photo, quality: 70);
    if (encoded.length <= maxSharedPhotoBytes) return encoded;
  }
  throw const FormatException('사진을 작게 줄이지 못했어요. 다른 사진을 골라 주세요.');
}
