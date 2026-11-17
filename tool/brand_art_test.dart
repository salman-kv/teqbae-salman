// Generates the app icon and splash artwork (PNG files in assets/).
//
// Run:  flutter test tool/brand_art_test.dart
//
// Design: a location pin with a check mark (attendance inside the office area)
// on the app's blue gradient. Everything is drawn with Flutter's canvas, so no
// image editor is needed. Output:
//   assets/icon/icon.png              full icon (gradient + pin), 1024
//   assets/icon/icon_background.png   adaptive icon background (gradient), 1024
//   assets/icon/icon_foreground.png   adaptive icon foreground (pin only), 1024
//   assets/splash/splash.png          launch screen logo (white pin), 960
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _navy = Color(0xFF0A2F7A);
const _blue = Color(0xFF1A5FDB);
const _sky = Color(0xFF3D8BFF);

/// Draws the pin with its centre-of-circle at the local origin.
/// Local geometry (units): circle radius 190, tip 340 below the centre.
void _glyph(
  Canvas c, {
  required double cx,
  required double cy,
  required double scale,
  bool ring = true,
  bool outerRing = false,
}) {
  c.save();
  c.translate(cx, cy);
  c.scale(scale);

  // Ripples on the ground under the pin: the "geofence".
  Paint ringPaint(double alpha) => Paint()
    ..color = Colors.white.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14
    ..isAntiAlias = true;
  if (ring) c.drawOval(Rect.fromCenter(center: const Offset(0, 340), width: 500, height: 132), ringPaint(0.42));
  if (outerRing) {
    c.drawOval(Rect.fromCenter(center: const Offset(0, 340), width: 680, height: 184), ringPaint(0.2));
  }

  // The pin, with a see-through hole (drawn on its own layer so "clear" only
  // cuts the pin, not what is behind it).
  c.saveLayer(const Rect.fromLTWH(-400, -300, 800, 800), Paint());
  final pin = Path.combine(
    PathOperation.union,
    Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 190)),
    Path()
      ..moveTo(0, 340)
      ..lineTo(-157.5, 106.2)
      ..lineTo(157.5, 106.2)
      ..close(),
  );
  c.drawPath(pin, Paint()..color = Colors.white..isAntiAlias = true);
  c.drawCircle(Offset.zero, 108, Paint()..blendMode = BlendMode.clear);
  c.restore();

  // The check mark inside the hole.
  final check = Path()
    ..moveTo(-52, 6)
    ..lineTo(-14, 44)
    ..lineTo(54, -34);
  c.drawPath(
    check,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true,
  );
  c.restore();
}

void _gradient(Canvas c, double size) {
  c.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size, size),
        const [_navy, _blue, _sky],
        const [0, 0.55, 1],
      ),
  );
}

Future<void> _save(WidgetTester tester, String path, int size, void Function(Canvas) draw) async {
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    draw(canvas);
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('generate icon and splash artwork', (tester) async {
    // Pin bounding box is y -190..340 (centre +75), so centre it by moving the
    // circle centre up by 75 * scale.
    double cy(double size, double scale) => size / 2 - 75 * scale;

    // 1) Full icon: gradient + pin + two ripples.
    await _save(tester, 'assets/icon/icon.png', 1024, (c) {
      _gradient(c, 1024);
      _glyph(c, cx: 512, cy: cy(1024, 1.1), scale: 1.1, outerRing: true);
    });

    // 2) Adaptive icon background: gradient only.
    await _save(tester, 'assets/icon/icon_background.png', 1024, (c) => _gradient(c, 1024));

    // 3) Adaptive icon foreground: pin on transparent, inside the 66% safe zone.
    await _save(tester, 'assets/icon/icon_foreground.png', 1024, (c) {
      _glyph(c, cx: 512, cy: cy(1024, 1.0), scale: 1.0);
    });

    // 4) Splash logo: white pin, no ripples, inside Android 12's 640px circle.
    await _save(tester, 'assets/splash/splash.png', 960, (c) {
      _glyph(c, cx: 480, cy: cy(960, 0.95), scale: 0.95, ring: false);
    });

    for (final f in [
      'assets/icon/icon.png',
      'assets/icon/icon_background.png',
      'assets/icon/icon_foreground.png',
      'assets/splash/splash.png',
    ]) {
      expect(File(f).existsSync(), isTrue, reason: f);
      expect(File(f).lengthSync(), greaterThan(1000), reason: f);
    }
  });
}
