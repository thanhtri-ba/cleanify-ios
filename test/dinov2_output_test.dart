import 'package:cleanify/engines/dino/dino_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts and normalizes the class token for each image', () {
    List<double> token(double value) => [value, ...List.filled(383, 0.0)];
    final raw = [
      [token(2), token(99)],
      [token(-3), token(99)],
    ];
    final embeddings = dinoV2ClassEmbeddings(raw, 2);
    expect(embeddings.length, 2);
    expect(embeddings[0].length, 384);
    expect(embeddings[0][0], 1);
    expect(embeddings[1][0], -1);
  });

  test('rejects incompatible DINOv2 output', () {
    expect(
      () => dinoV2ClassEmbeddings([
        [
          [1.0],
        ],
      ], 1),
      throwsStateError,
    );
    expect(() => dinoV2ClassEmbeddings([], 1), throwsStateError);
  });
}
