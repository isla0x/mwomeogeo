import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mwomeogeo/shared_photo.dart';

void main() {
  test('large noisy photo fits Spark limit with the same aspect ratio', () {
    final random = Random(7);
    final source = img.Image(width: 1400, height: 1000);
    for (final pixel in source) {
      pixel.setRgb(
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
      );
    }
    final result = encodeSharedPhoto(img.encodePng(source));
    expect(result.length, lessThanOrEqualTo(maxSharedPhotoBytes));
    final photo = img.decodeJpg(result)!;
    expect(photo.width, lessThanOrEqualTo(960));
    expect(photo.width / photo.height, closeTo(1.4, .01));
  });
  test('small PNG stays small and invalid input fails', () {
    final result = encodeSharedPhoto(
      img.encodePng(img.Image(width: 30, height: 40)),
    );
    expect(img.decodeJpg(result)!.width, 30);
    expect(
      () => encodeSharedPhoto(Uint8List.fromList([0, 1, 2])),
      throwsFormatException,
    );
  });
}
