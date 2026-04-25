import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';

enum Piece {
  all('A',0),
  pawn('P',1),
  knight('N',2),
  bishop('B',3),
  rook('R',4),
  queen('Q',5),
  king('K',6);
  final int id;
  final String letter;
  const Piece(this.letter,this.id);

  static Piece? byNum(int n) {
    for (final p in Piece.values) {
      if (p.id == n) return p;
    }
    return null;
  }

  static Piece? byLetter(String l) {
    for (final p in Piece.values) {
      if (p.letter == l) return p;
    }
    return null;
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const int maxPly = 127;
const int numPieces = 7; // 0 = all, 1..6 = pawn..king
const int numSquares = 64;

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

class ChessStat {
  List<List<List<int>>>? counts;

  Future<void> calcPieces(String assetPath) async {
    final data = await rootBundle.loadString(assetPath);
    counts = await compute(parsePgnWorker, data);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate entry point (MUST be top-level)
// ─────────────────────────────────────────────────────────────────────────────

List<List<List<int>>> parsePgnWorker(String data) {
  final counts = createCounts();

  int start = 0;

  for (int i = 0; i <= data.length; i++) {
    if (i == data.length || data.codeUnitAt(i) == 10) {
      final lineStart = start;
      final lineEnd = i;

      // Fast check for lines starting with "1."
      if (lineEnd - lineStart > 2 &&
          data.codeUnitAt(lineStart) == 49 && // '1'
          data.codeUnitAt(lineStart + 1) == 46) { // '.'
        parseLineFast(data, lineStart, lineEnd, counts);
      }

      start = i + 1;
    }
  }

  return counts;
}

// ─────────────────────────────────────────────────────────────────────────────
// Core parsing (zero substring version)
// ─────────────────────────────────────────────────────────────────────────────

void parseLineFast(
    String data,
    int start,
    int end,
    List<List<List<int>>> counts,
    ) {
  int tokenStart = start;
  int ply = 0;

  for (int i = start; i <= end; i++) {
    if (i == end || data.codeUnitAt(i) == 32) {
      if (i > tokenStart) {
        final first = data.codeUnitAt(tokenStart);

        // Skip move numbers (tokens starting with digit)
        if (first < 48 || first > 57) {
          parseMoveFast(data, tokenStart, i, ply, counts);
          ply++;
        }
      }
      tokenStart = i + 1;
    }
  }
}

void parseMoveFast(
    String s,
    int start,
    int end,
    int ply,
    List<List<List<int>>> counts,
    ) {
  if (ply > maxPly) return;

  int piece = 1; // pawn default
  int square = -1;

  final first = s.codeUnitAt(start);

  // ── Castling ───────────────────────────────────────────────────────────────
  if (first == 79) { // 'O'
    final isLong = (end - start) >= 5; // "O-O-O"
    final isBlack = (ply & 1) == 1;

    piece = 6; // king
    square = isLong ? 2 : 6;
    if (isBlack) square += 56;
  }

  // ── Normal moves ───────────────────────────────────────────────────────────
  else {
    // Piece detection
    if (first >= 65 && first <= 90) {
      switch (first) {
        case 78: piece = 2; break; // N
        case 66: piece = 3; break; // B
        case 82: piece = 4; break; // R
        case 81: piece = 5; break; // Q
        case 75: piece = 6; break; // K
        default: piece = 1;        // P
      }
    }

    // Find destination square from end
    for (int i = end - 1; i >= start + 1; i--) {
      final c = s.codeUnitAt(i);

      if (c >= 49 && c <= 56) { // '1'..'8'
        final file = s.codeUnitAt(i - 1) - 97; // 'a'..'h'
        final rank = c - 49;
        square = rank * 8 + file;
        break;
      }
    }
  }

  if (square < 0) return;

  counts[ply][piece][square]++;
  counts[ply][0][square]++; // "all"
}

// ─────────────────────────────────────────────────────────────────────────────
// Data structure
// ─────────────────────────────────────────────────────────────────────────────

List<List<List<int>>> createCounts() {
  return List.generate(
    maxPly + 1,
        (_) => List.generate(
      numPieces,
          (_) => List.filled(numSquares, 0),
    ),
  );
}
