import 'dart:math';
import 'package:chess_stats/stats.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'grid_tex.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Piece/Square Visualizer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Chess Piece/Square Visualizer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────────
  bool initialized = false;   // PGN parsed
  bool cacheReady = false;    // full texture cache built for current piece
  bool crossFade = false;
  int maxPly = 127;
  Piece piece = Piece.all;
  late ChessStat stats;

  // Full texture cache: piece → ply → GridTexture.
  // Built upfront for the selected piece so playback is purely synchronous.
  final Map<Piece, Map<int, GridTexture>> _texCache = {};

  // Two textures currently being cross-faded.
  GridTexture? texA;
  GridTexture? texB;
  int _displayPly = 0;
  int _plyB = 0;

  // ── Animation ──────────────────────────────────────────────────────────────
  late final AnimationController _ctrl;
  late final Animation<double> _tween;
  bool _playing = false;

  // Milliseconds per ply step during auto-play.
  static const int _stepMs = 160;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _stepMs),
    );
    _tween = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _snapToB();
        if (_playing) _advancePlay();
      }
    });

    stats = ChessStat();
    stats
        .calcPieces("pgn/lichess_db_standard_rated_2013-01.pgn")
        .then((_) => _onStatsReady());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  /// Called once the PGN has been parsed. Shows the UI immediately with ply 0,
  /// then builds the full texture cache for the default piece in the background.
  Future<void> _onStatsReady() async {
    if (!mounted) return;
    setState(() => initialized = true);
    await _warmCache(piece);
    if (!mounted) return;
    final t = _texCache[piece]![0]!;
    setState(() {
      cacheReady = true;
      texA = t;
      texB = t;
      _plyB = 0;
      _displayPly = 0;
    });
  }

  // ── Texture building ───────────────────────────────────────────────────────

  Float64List _buildGrid(Map<String, int> map) {
    final raw = Float64List(64);
    for (int rank = 1; rank <= 8; rank++) {
      for (int file = 0; file < 8; file++) {
        final sq = '${String.fromCharCode(97 + file)}$rank';
        final idx = (8 - rank) * 8 + file;
        raw[idx] = (map[sq] ?? 0).toDouble();
      }
    }

    final nonZero = raw.where((v) => v > 0).toList();
    if (nonZero.isEmpty) return raw;

    final mean = nonZero.reduce((a, b) => a + b) / nonZero.length;
    final variance = nonZero
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) /
        nonZero.length;
    final std = sqrt(variance);

    const sigmaRange = 2.5;
    final grid = Float64List(64);
    for (int i = 0; i < 64; i++) {
      if (raw[i] == 0) {
        grid[i] = 0.0;
      } else {
        final z = std > 0 ? (raw[i] - mean) / std : 0.0;
        grid[i] = ((z / sigmaRange) + 1.0) / 2.0;
        grid[i] = grid[i].clamp(0.05, 1.0);
      }
    }
    return grid;
  }

  Color _heatColor(double v) {
    v = v.clamp(0.0, 1.0);
    const stops = [
      [0.05, 0.05, 0.55],
      [0.00, 0.55, 0.75],
      [0.05, 0.65, 0.15],
      [0.95, 0.70, 0.00],
      [0.95, 0.05, 0.05],
    ];
    final scaled = v * (stops.length - 1);
    final lo = scaled.floor().clamp(0, stops.length - 2);
    final hi = lo + 1;
    final t = scaled - lo;
    final r = stops[lo][0] + (stops[hi][0] - stops[lo][0]) * t;
    final g = stops[lo][1] + (stops[hi][1] - stops[lo][1]) * t;
    final b = stops[lo][2] + (stops[hi][2] - stops[lo][2]) * t;
    return Color.fromARGB(
        255, (r * 255).round(), (g * 255).round(), (b * 255).round());
  }

  Future<GridTexture> _buildTexture(Piece p, int ply) {
    final map = stats.pieceCoordMapByPly[ply]?[p] ?? {};
    final grid = _buildGrid(map);
    return GridTexture.build(
      gridW: 8,
      gridH: 8,
      values: grid,
      pxPerCell: 32,
      colorFn: _heatColor,
    );
  }

  /// Builds and caches textures for all plies of [p] if not already cached.
  /// Yields between batches so the UI stays responsive during the build.
  Future<void> _warmCache(Piece p) async {
    if (_texCache.containsKey(p)) return; // already done
    _texCache[p] = {};
    const batchSize = 8;
    for (int ply = 0; ply <= maxPly; ply += 2) {
      _texCache[p]![ply] = await _buildTexture(p, ply);
      // Yield to the event loop every [batchSize] textures so frames can paint.
      if ((ply ~/ 2) % batchSize == 0) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  // ── Navigation — all synchronous once cache is warm ────────────────────────

  /// Snap to [ply] with no animation.
  void _jumpTo(int ply, {animating = false}) {
    print("Jumping to: $ply");
    if (!animating) _ctrl.stop();
    final tex = _texCache[piece]?[ply];
    if (tex == null) return;
    print("Setting state at: $ply");
    setState(() {
      texA = tex;
      texB = tex;
      _plyB = ply;
      _displayPly = ply;
      if (!animating) _ctrl.value = 0;
    });
  }

  /// Start a cross-fade from the current frame to [targetPly].
  void _animateTo(int targetPly) {
    if (targetPly == _plyB) return;
    final tex = _texCache[piece]?[targetPly];
    if (tex == null) return;
    setState(() {
      texB = tex;
      _plyB = targetPly;
      _displayPly = targetPly;
    });
    _ctrl.forward(from: 0);
  }

  void _snapToB() {
    setState(() {
      texA = texB;
      _ctrl.value = 0;
    });
  }

  void _advancePlay() {
    final next = _plyB + 2;
    if (next > maxPly) {
      _jumpTo(0);
      if (_playing) _advancePlay();
    } else {
      if (crossFade) {
        _animateTo(next);
      } else {
        _jumpTo(next, animating: true);
        Future.delayed(Duration(milliseconds: 60)).then((v) => _ctrl.forward(from: 0));
      }
    }
  }

  // ── Transport controls ─────────────────────────────────────────────────────
  void _togglePlay() {
    if (_playing) {
      setState(() => _playing = false);
      _ctrl.stop();
    } else {
      setState(() => _playing = true);
      _advancePlay();
    }
  }

  void _stepBack() {
    _ctrl.stop();
    setState(() => _playing = false);
    _animateTo((_plyB - 2).clamp(0, maxPly));
  }

  void _stepForward() {
    _ctrl.stop();
    setState(() => _playing = false);
    _animateTo((_plyB + 2).clamp(0, maxPly));
  }

  /// Switch piece: warm its cache if needed (shows a spinner), then jump.
  void _setPiece(Piece p) async {
    _ctrl.stop();
    setState(() {
      _playing = false;
      piece = p;
      cacheReady = false;
    });
    await _warmCache(p);
    if (!mounted) return;
    setState(() => cacheReady = true);
    _jumpTo(_plyB);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: !initialized
            ? const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading PGN data…'),
          ],
        )
            : !cacheReady
            ? const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Building texture cache…'),
          ],
        )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // ── Piece selector ────────────────────────────────────────────────
          Wrap(
            spacing: 4,
            children: Piece.values.map((p) {
              return FilterChip(
                label: Text(p.letter.toUpperCase()),
                selected: p == piece,
                onSelected: (_) => _setPiece(p),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // ── Heatmap ───────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _tween,
            builder: (context, _) => _CrossFadeHeatmap(
              texA: texA?.image,
              texB: texB?.image,
              t: _tween.value,
              size: 280,
            ),
          ),
          const SizedBox(height: 10),

          // ── Ply label ─────────────────────────────────────────────────────
          Text(
            'Piece: ${piece.name}   '
                'Ply $_displayPly / $maxPly  '
                '(move ${(_displayPly / 2).ceil()})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),

          // ── Slider ────────────────────────────────────────────────────────
          Slider(
            min: 0,
            max: maxPly.toDouble(),
            divisions: maxPly ~/ 2,
            value: _displayPly.toDouble().clamp(0, maxPly.toDouble()),
            onChangeStart: (_) {
              _ctrl.stop();
              setState(() => _playing = false);
            },
            onChanged: (v) {
              final ply = (v / 2).round() * 2;
              _jumpTo(ply);
            },
            onChangeEnd: (v) {
              final ply = (v / 2).round() * 2;
              _jumpTo(ply);
            },
          ),

          // ── Transport bar ─────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Rewind to start',
                onPressed: () {
                  setState(() => _playing = false);
                  _jumpTo(0);
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Back 1 ply',
                onPressed: _stepBack,
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                tooltip: _playing ? 'Pause' : 'Play',
                onPressed: _togglePlay,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Forward 1 ply',
                onPressed: _stepForward,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: 'Skip to end',
                onPressed: () {
                  setState(() => _playing = false);
                  _jumpTo(maxPly);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Cross-fade heatmap ────────────────────────────────────────────────────────

/// Paints [texA] at opacity (1−t) then [texB] at opacity t, giving a smooth
/// pixel-level cross-fade between two heatmap frames. No widget rebuilds or
/// new texture allocations happen during the tween — only paint() is called.
class _CrossFadeHeatmap extends StatelessWidget {
  const _CrossFadeHeatmap({
    required this.texA,
    required this.texB,
    required this.t,
    required this.size,
  });

  final ui.Image? texA;
  final ui.Image? texB;
  final double t;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeatmapCrossFadePainter(texA: texA, texB: texB, t: t),
      ),
    );
  }
}

class _HeatmapCrossFadePainter extends CustomPainter {
  _HeatmapCrossFadePainter({
    required this.texA,
    required this.texB,
    required this.t,
  });

  final ui.Image? texA;
  final ui.Image? texB;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);

    void drawTex(ui.Image img, double opacity) {
      if (opacity <= 0) return;
      final src =
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.low
          ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255),
      );
    }

    if (texA != null) drawTex(texA!, 1.0 - t);
    if (texB != null) drawTex(texB!, t);
  }

  @override
  bool shouldRepaint(_HeatmapCrossFadePainter old) =>
      old.t != t || old.texA != texA || old.texB != texB;
}
