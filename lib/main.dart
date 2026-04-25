import 'dart:math';
import 'package:chess_stats/stats.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'grid_tex.dart';

enum ViewMode {
  rawCounts,   // original Map-based behavior
  normalized,  // current z-score / max-normalized version
}

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
  ViewMode mode = ViewMode.normalized;
  TextStyle txtStyle1 = TextStyle(color: Colors.white);
  TextStyle txtStyle2 = TextStyle(color: Colors.black);
  bool initialized = false;   // PGN parsed
  bool cacheReady = false;    // full texture cache built for current piece
  int maxPly = 127;
  Piece piece = Piece.all;
  late ChessStat stats;

  // Full texture cache: piece → ply → GridTexture.
  // Built upfront for the selected piece so playback is purely synchronous.
  final Map<Piece, Map<int, GridTexture>> _texCache = {};

  // Two textures currently being cross-faded.
  GridTexture? _tex;
  int _ply = 0;

  // ── Animation ──────────────────────────────────────────────────────────────
  bool _playing = false;
  // Milliseconds per ply step during auto-play.
  static const int _stepMs = 160;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    stats = ChessStat();
    stats
        .calcPieces("pgn/lichess_db_standard_rated_2013-01.pgn")
        .then((_) => _onStatsReady());
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
      _tex = t;
      _ply = 0;
    });
  }

  // ── Texture building ───────────────────────────────────────────────────────

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
    final values = switch (mode) {
      ViewMode.rawCounts => _buildRawTexture(p, ply),
      ViewMode.normalized => _buildNormalizedTexture(p, ply)
    };
    return GridTexture.build(
        gridW: 8,
        gridH: 8,
        values: values,
        pxPerCell: 32,
        colorFn: _heatColor,
        flip: true
    );
  }

  Float64List _buildNormalizedTexture(Piece p, int ply) {
    final pieceIndex = p.id;
    final counts = stats.counts![ply][pieceIndex];

    final values = Float64List(64);

    double max = 1;
    for (final v in counts) {
      if (v > max) max = v.toDouble();
    }

    for (int i = 0; i < 64; i++) {
      values[i] = counts[i] / max;
    }

    return values;
  }

  Float64List _buildRawTexture(Piece p, int ply) {
    final pieceIndex = p.id;
    final counts = stats.counts![ply][pieceIndex];

    final values = Float64List(64);

    double max = 1;
    for (final v in counts) {
      if (v > max) max = v.toDouble();
    }

    for (int i = 0; i < 64; i++) {
      values[i] = counts[i].toDouble();
    }

    return values;
  }

  Future<void> _rebuildCurrentTexture() async {
    if (!cacheReady) return;

    final tex = await _buildTexture(piece, _ply);

    if (!mounted) return;

    setState(() {
      _tex = tex;
    });
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

  void _stop() {
    setState(() => _playing = false);
  }

  // ── Navigation — all synchronous once cache is warm ────────────────────────

  /// Snap to [ply] with no animation.
  void _jumpTo(int ply, {animating = false}) {
    if (!animating) _stop();
    final tex = _texCache[piece]?[ply];
    if (tex == null) return;
    setState(() {
      _tex = tex;
      _ply = ply;
    });
  }

  void _nextStep() {
    if (!_playing) return;
    final next = _ply + 2;
    if (next > maxPly) {
      _jumpTo(0);
      _nextStep();
    } else {
      _jumpTo(next, animating: true);
      Future.delayed(Duration(milliseconds: _stepMs)).then((v) => _nextStep());
    }
  }

  // ── Transport controls ─────────────────────────────────────────────────────
  void _togglePlay() {
    if (_playing) {
      _stop();
    } else {
      _playing = true;
      _nextStep();
    }
  }

  void _stepBack() {
    _stop();
    _jumpTo((_ply - 2).clamp(0, maxPly));
  }

  void _stepForward() {
    _stop();
    _jumpTo((_ply + 2).clamp(0, maxPly));
  }

  /// Switch piece: warm its cache if needed (shows a spinner), then jump.
  void _setPiece(Piece p) async {
    _stop();
    setState(() {
      _playing = false;
      piece = p;
      cacheReady = false;
    });
    await _warmCache(p);
    if (!mounted) return;
    setState(() => cacheReady = true);
    _jumpTo(_ply);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: ColoredBox(color: Colors.black, child: Center(
        child: !initialized
            ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading PGN data…', style: txtStyle1),
          ],
        )
            : !cacheReady
            ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Building texture cache…', style: txtStyle1),
          ],
        )
            : _buildBody(),
      ),
    ));
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ColoredBox(color: Colors.cyan, child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("This app visualizes the probabilities of a given piece moving to a given square on a given move in chess.",style: txtStyle2),
          Text("Blue: rare, Green: common, Red: likely",style: txtStyle2),
          SizedBox(height: 24),
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
          RawImage(image: _tex?.image),
          const SizedBox(height: 10),

          // ── Ply label ─────────────────────────────────────────────────────
          Text(
            'Piece: ${piece.name}   '
                'Ply $_ply / $maxPly  '
                '(move ${(_ply / 2).ceil()})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),

          // ── Slider ────────────────────────────────────────────────────────
          Slider(
            min: 0,
            max: maxPly.toDouble(),
            divisions: maxPly ~/ 2,
            value: _ply.toDouble().clamp(0, maxPly.toDouble()),
            onChangeStart: (_) {
              _stop();
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
    ));
  }
}

