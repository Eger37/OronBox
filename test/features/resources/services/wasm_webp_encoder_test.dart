import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oronbox/src/features/resources/services/resource_image_processor.dart';
import 'package:wasm_run_flutter/wasm_run_flutter.dart';
import 'package:oronbox/src/core/wasm/wasm_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // `flutter test` does not link native assets into the test VM, so point
    // the wasm_run FFI at the dynamic library the package build hook fetched
    // during pub get. `build/native_assets/<os>/` is where the toolchain
    // publishes hook outputs; the official override is the
    // WASM_RUN_DART_DYNAMIC_LIBRARY environment variable.
    final (name, osDir) = switch (true) {
      _ when Platform.isMacOS => ('libwasm_run_dart.dylib', 'macos'),
      _ when Platform.isLinux => ('libwasm_run_dart.so', 'linux'),
      _ when Platform.isWindows => ('wasm_run_dart.dll', 'windows'),
      _ => ('', ''),
    };
    final candidates = [
      Platform.environment['WASM_RUN_DART_DYNAMIC_LIBRARY'],
      if (name.isNotEmpty) ...[
        'build/native_assets/$osDir/$name',
        '.dart_tool/lib/$name',
      ],
    ];
    final path = candidates.firstWhere(
      (candidate) => candidate != null && File(candidate).existsSync(),
      orElse: () => null,
    );
    if (path == null) {
      fail(
        'wasm_run native library not fetched; run `flutter pub get` and '
        'any flutter build/test once before the test suite.',
      );
    }
    await WasmRunLibrary.setUp(lib: ExternalLibrary.open(path));
  });

  test('indexed PNG pixels are expanded to RGBA before WebP encoding', () {
    final palette = img.PaletteUint8(2, 4)
      ..setRgba(0, 12, 34, 56, 255)
      ..setRgba(1, 210, 180, 90, 128);
    final indexed =
        img.Image(
            width: 2,
            height: 1,
            numChannels: 1,
            withPalette: true,
            palette: palette,
          )
          ..setPixelIndex(0, 0, 0)
          ..setPixelIndex(1, 0, 1);
    final decoded = img.decodePng(img.encodePng(indexed));
    expect(decoded, isNotNull);

    expect(
      materializeResourceImageRgba(decoded!),
      Uint8List.fromList([12, 34, 56, 255, 210, 180, 90, 128]),
    );
  });

  test('libwebp wasm encodes RGBA into a valid WebP payload', () async {
    final bytes = await File('assets/wasm/webp_encoder.wasm').readAsBytes();
    final scope = WasmRuntime.shared.openScope('test.webp-encoder');
    addTearDown(scope.dispose);
    final instance = await scope.instantiate(
      bytes,
      configure: (builder) => builder.addImport(
        'wasi_snapshot_preview1',
        'proc_exit',
        WasmFunction.voidReturn(
          (int code) => throw StateError('libwebp exited with code $code'),
          params: const [ValueTy.i32],
        ),
      ),
    );
    final memory = instance.memory('memory');

    const width = 8, height = 8;
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 200;
      rgba[i + 1] = 80;
      rgba[i + 2] = 40;
      rgba[i + 3] = 255;
    }
    int intResult(List<Object?> results) => (results.first as num).toInt();

    final input = intResult(instance.call('zb_alloc', [rgba.length]));
    expect(input, isNonZero);
    memory.view.setAll(input, rgba);
    final size = intResult(
      instance.call('zb_webp_encode', [input, width, height, 75.0]),
    );
    expect(size, greaterThan(0));
    final output = intResult(instance.call('zb_webp_output'));
    final webp = memory.view.sublist(output, output + size);
    // RIFF....WEBP container magic
    expect(String.fromCharCodes(webp.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(webp.sublist(8, 12)), 'WEBP');
  });
}
