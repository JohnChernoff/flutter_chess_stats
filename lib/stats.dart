import 'package:flutter/services.dart' show rootBundle;

enum Side { white, black }

enum Piece {
  all('A'),
  pawn('P'),
  knight('N'),
  bishop('B'),
  rook('R'),
  queen('Q'),
  king('K');

  final String letter;
  const Piece(this.letter);

  static Piece? getPiece(String letter) {
    for (final p in Piece.values) {
      if (p.letter == letter) return p;
    }
    return null;
  }
}

class ChessStat {
  // ply -> piece -> count
  final Map<int, Map<Piece, int>> pieceMapByPly = {};

  // ply -> piece -> square -> count
  final Map<int, Map<Piece, Map<String, int>>> pieceCoordMapByPly = {};

  Future<void> calcPieces(String assetPath) async {
    final data = await rootBundle.loadString(assetPath);
    final lines = data.split('\n');

    for (final line in lines) {
      if (line.startsWith('1.')) {
        final tokens = line.split(' ');
        int ply = 0;

        for (final token in tokens) {
          if (!token.contains('.')) {
            parseMove(token, ply);
            ply++;
          }
        }
      }
    }
  }

  void initPly(int ply) {
    pieceMapByPly.putIfAbsent(ply, () => {});
    pieceCoordMapByPly.putIfAbsent(ply, () => {});

    for (final piece in Piece.values) {
      pieceMapByPly[ply]!.putIfAbsent(piece, () => 0);
      pieceCoordMapByPly[ply]!.putIfAbsent(piece, () => {});
    }
  }

  void parseMove(String token, int ply) {
    initPly(ply);

    final side = (ply % 2 == 0) ? Side.white : Side.black;
    String square;

    if (token.startsWith('O-O-O')) {
      square = (side == Side.black) ? 'c8' : 'c1';
      incPiece(Piece.king, ply);
      incPiece(Piece.all, ply);
      incPieceSquare(Piece.king, square, ply);
    } else if (token.startsWith('O-O')) {
      square = (side == Side.black) ? 'g8' : 'g1';
      incPiece(Piece.king, ply);
      incPiece(Piece.all, ply);
      incPieceSquare(Piece.king, square, ply);
    } else {
      final pChar = token.substring(0, 1);
      final piece =
      isUppercase(pChar) ? Piece.getPiece(pChar) : Piece.pawn;

      if (piece == null) return;

      incPiece(piece, ply);
      incPiece(Piece.all, ply);

      int i = token.length - 1;
      while (i >= 0 && !isNumeric(token[i])) {
        i--;
      }

      if (i > 0) {
        square = token.substring(i - 1, i + 1);
        incPieceSquare(piece, square, ply);
        incPieceSquare(Piece.all, square, ply);
      }
    }
  }

  void incPiece(Piece piece, int ply) {
    pieceMapByPly[ply]![piece] =
        (pieceMapByPly[ply]![piece] ?? 0) + 1;
  }

  void incPieceSquare(Piece piece, String square, int ply) {
    final map = pieceCoordMapByPly[ply]![piece]!;
    map[square] = (map[square] ?? 0) + 1;
  }

  bool isUppercase(String s) => s == s.toUpperCase();

  bool isNumeric(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  void dumpStats(int ply) {
    final totalMoves = pieceMapByPly[ply]?[Piece.all] ?? 0;

    log('\n=== Piece Move Percentages ===');
    for (final p in Piece.values) {
      if (p == Piece.all) continue;
      final count = pieceMapByPly[ply]?[p] ?? 0;
      final pct =
      totalMoves == 0 ? 0 : (100.0 * count / totalMoves);

      log('${p.name.padRight(6)}: $count (${pct.toStringAsFixed(2)}%)');
    }
  }

  void log(String msg) {
    print(msg);
  }
}
