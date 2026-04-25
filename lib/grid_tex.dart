import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GridTexture {
  final ui.Image image;
  final Float64List values;
  final int gridW;
  final int gridH;
  final int pxPerCell;

  GridTexture(
      this.image,
      this.values,
      this.gridW,
      this.gridH,
      this.pxPerCell,
      );

  static Future<GridTexture> build({
    required int gridW,
    required int gridH,
    required Float64List values,
    int pxPerCell = 8,
    Color Function(double value)? colorFn,
    bool smooth = true,
    bool flip = false,
  }) async {
    final mw = gridW * pxPerCell;
    final mh = gridH * pxPerCell;
    final rgba = Uint8List(mw * mh * 4);

    colorFn ??= _defaultHeatColor;

    for (int py = 0; py < mh; py++) {
      for (int px = 0; px < mw; px++) {
        final i = py * mw + px;

        final sx = (px + 0.5) / pxPerCell;
        final sy = flip
          ? gridH - 1 - ((py + 0.5) / pxPerCell)
          : (py + 0.5) / pxPerCell;

        final value = smooth
            ? sampleBilinear(sx, sy, gridW, gridH, values)
            : sampleNearest(sx, sy, gridW, gridH, values);

        final c = colorFn(value);

        final off = i * 4;
        rgba[off] = c.red;
        rgba[off + 1] = c.green;
        rgba[off + 2] = c.blue;
        rgba[off + 3] = c.alpha;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      mw,
      mh,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final image = await completer.future;

    return GridTexture(image, values, gridW, gridH, pxPerCell);
  }

  // -------------------------
  // Sampling
  // -------------------------

  static double sampleBilinear(
      double sx,
      double sy,
      int w,
      int h,
      Float64List data,
      ) {
    final fx = sx - 0.5;
    final fy = sy - 0.5;

    final x0 = fx.floor();
    final y0 = fy.floor();

    final tx = fx - x0;
    final ty = fy - y0;

    final v00 = _at(data, x0, y0, w, h);
    final v10 = _at(data, x0 + 1, y0, w, h);
    final v01 = _at(data, x0, y0 + 1, w, h);
    final v11 = _at(data, x0 + 1, y0 + 1, w, h);

    return _lerp(
      _lerp(v00, v10, tx),
      _lerp(v01, v11, tx),
      ty,
    );
  }

  static double sampleNearest(
      double sx,
      double sy,
      int w,
      int h,
      Float64List data,
      ) {
    final x = sx.floor();
    final y = sy.floor();
    return _at(data, x, y, w, h);
  }

  static double _at(Float64List data, int x, int y, int w, int h) {
    final cx = x.clamp(0, w - 1);
    final cy = y.clamp(0, h - 1);
    return data[cy * w + cx];
  }

  static double _lerp(double a, double b, double t) =>
      a * (1 - t) + b * t;

  // -------------------------
  // Default heat color
  // -------------------------

  static Color _defaultHeatColor(double v) {
    v = v.clamp(0.0, 1.0);

    final r = (255 * v).toInt();
    final b = (255 * (1 - v)).toInt();

    return Color.fromARGB(255, r, 0, b);
  }

}
