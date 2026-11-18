import 'package:cleanify/core/scanner/cross_group_reconcile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('near-duplicate policy uses PDQ or PDQ plus centered cosine', () {
    const maxHamming = 32;
    const similarMaxHamming = 64;
    const modelMinCosine = 0.8;
    expect(
      nearDuplicatePairEvidence(
        hamming: 32,
        pdqQualityOk: true,
        centeredCosine: null,
        maxHamming: maxHamming,
        similarMaxHamming: similarMaxHamming,
        modelMinCosine: modelMinCosine,
      ),
      isTrue,
    );
    expect(
      nearDuplicatePairEvidence(
        hamming: 64,
        pdqQualityOk: true,
        centeredCosine: 0.8,
        maxHamming: maxHamming,
        similarMaxHamming: similarMaxHamming,
        modelMinCosine: modelMinCosine,
      ),
      isTrue,
    );
    expect(
      nearDuplicatePairEvidence(
        hamming: 64,
        pdqQualityOk: true,
        centeredCosine: 0.79,
        maxHamming: maxHamming,
        similarMaxHamming: similarMaxHamming,
        modelMinCosine: modelMinCosine,
      ),
      isFalse,
    );
    expect(
      nearDuplicatePairEvidence(
        hamming: null,
        pdqQualityOk: null,
        centeredCosine: 0.99,
        maxHamming: maxHamming,
        similarMaxHamming: similarMaxHamming,
        modelMinCosine: modelMinCosine,
      ),
      isFalse,
    );
    expect(
      nearDuplicatePairEvidence(
        hamming: 20,
        pdqQualityOk: false,
        centeredCosine: 0.99,
        maxHamming: maxHamming,
        similarMaxHamming: similarMaxHamming,
        modelMinCosine: modelMinCosine,
      ),
      isFalse,
    );
  });

  test('burst-like policy uses capture gap and raw cosine independently', () {
    expect(
      burstLikePairEvidence(
        gapMs: 15000,
        rawCosine: 0.70,
        burstWindowMs: 15000,
        burstMinRawCosine: 0.70,
      ),
      isTrue,
    );
    expect(
      burstLikePairEvidence(
        gapMs: 15001,
        rawCosine: 0.99,
        burstWindowMs: 15000,
        burstMinRawCosine: 0.70,
      ),
      isFalse,
    );
    expect(
      burstLikePairEvidence(
        gapMs: 100,
        rawCosine: 0.69,
        burstWindowMs: 15000,
        burstMinRawCosine: 0.70,
      ),
      isFalse,
    );
  });

  test('merges only with two independent matches covering both groups', () {
    final result = reconcileSimilarPartitions(
      partitions: const [
        [0, 1],
        [2, 3],
      ],
      matches: (a, b) => (a == 0 && b == 2) || (a == 1 && b == 3),
      gapMs: (_, __) => 1000,
    );
    expect(result, [
      [0, 1, 2, 3],
    ]);
  });

  test('one cross edge cannot merge whole groups', () {
    final result = reconcileSimilarPartitions(
      partitions: const [
        [0, 1],
        [2, 3],
      ],
      matches: (a, b) => a == 0 && b == 2,
      gapMs: (_, __) => 1000,
    );
    expect(result, [
      [0, 1],
      [2, 3],
    ]);
  });

  test('every photo in the smaller split group needs supporting evidence', () {
    const partitions = [
      [0, 1, 2, 3, 4, 5],
      [6, 7, 8],
    ];
    final withoutLastPhoto = reconcileSimilarPartitions(
      partitions: partitions,
      matches: (a, b) => (a == 0 && b == 6) || (a == 1 && b == 7),
      gapMs: (_, __) => 1000,
    );
    expect(withoutLastPhoto, partitions);

    final withEverySmallGroupPhoto = reconcileSimilarPartitions(
      partitions: partitions,
      matches: (a, b) =>
          (a == 0 && b == 6) || (a == 1 && b == 7) || (a == 2 && b == 8),
      gapMs: (_, __) => 1000,
    );
    expect(withEverySmallGroupPhoto, [
      [0, 1, 2, 3, 4, 5, 6, 7, 8],
    ]);
  });

  test('complete-link rule blocks chain merging', () {
    final result = reconcileSimilarPartitions(
      partitions: const [
        [0, 1],
        [2, 3],
        [4, 5],
      ],
      matches: (a, b) =>
          (a < 2 && b >= 2 && b < 4) || (a >= 2 && a < 4 && b >= 4),
      gapMs: (_, __) => 1000,
    );
    expect(
      result,
      equals([
        [0, 1, 2, 3],
        [4, 5],
      ]),
    );
  });

  test(
    'incomplete feature coverage fails closed when pair budget is reached',
    () {
      final result = reconcileSimilarPartitions(
        partitions: const [
          [0, 1],
          [2, 3],
        ],
        matches: (_, __) => true,
        gapMs: (_, __) => 1000,
        maxPairChecks: 3,
      );
      expect(result, [
        [0, 1],
        [2, 3],
      ]);
    },
  );
}
