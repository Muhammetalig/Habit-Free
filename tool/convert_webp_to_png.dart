// Simple converter using 'image' package to convert a WebP file to PNG.
// Usage: dart run tool/convert_webp_to_png.dart "C:/path/to/logo.webp" "assets/icons/app_icon.png"
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Kullanım: dart run tool/convert_webp_to_png.dart <girdi.webp> <cikti.png>',
    );
    exit(64);
  }
  final input = File(args[0]);
  final output = File(args[1]);
  if (!input.existsSync()) {
    stderr.writeln('Girdi bulunamadı: ${input.path}');
    exit(66);
  }
  final bytes = await input.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('WebP decode başarısız. Dosyayı kontrol edin.');
    exit(65);
  }
  // Opsiyonel: ikonu kare yapmak için letterbox/pad
  final size = decoded.width > decoded.height ? decoded.width : decoded.height;
  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 0)); // transparent background
  final dx = (size - decoded.width) ~/ 2;
  final dy = (size - decoded.height) ~/ 2;
  img.compositeImage(canvas, decoded, dstX: dx, dstY: dy);

  final png = img.encodePng(canvas);
  output.createSync(recursive: true);
  await output.writeAsBytes(png, flush: true);
  stdout.writeln('PNG yazıldı: ${output.path}');
}
