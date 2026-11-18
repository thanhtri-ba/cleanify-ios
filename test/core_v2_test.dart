import 'package:cleanify/core/scanner/core_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PairVerdict verify({int? hamming, double? cosine, bool sameCapture = true}) =>
      verifyNearPair(
        sameCaptureType: sameCapture,
        hamming: hamming,
        cosine: cosine,
        maxHamming: 32,
        candidateHamming: 64,
        minCosine: 0.93,
      );

  test('rollout defaults to V1 and recognizes explicit V2 modes', () {
    expect(CoreMode.parse(''), CoreMode.v2Active);
    expect(CoreMode.parse('unknown'), CoreMode.v2Active);
    expect(CoreMode.parse('V1_ONLY'), CoreMode.v1Only);
    expect(CoreMode.parse('V2_DISABLED'), CoreMode.v2Disabled);
    expect(CoreMode.parse('V2_SHADOW'), CoreMode.v2Shadow);
    expect(CoreMode.parse('V2_ACTIVE'), CoreMode.v2Active);
  });

  test('verification requires corroboration and preserves uncertainty', () {
    expect(verify(hamming: 32, cosine: 0.93), PairVerdict.confirmed);
    expect(verify(hamming: 32), PairVerdict.uncertain);
    expect(verify(hamming: 32, cosine: double.nan), PairVerdict.uncertain);
    expect(verify(hamming: 65, cosine: 0.8), PairVerdict.rejected);
    expect(verify(sameCapture: false), PairVerdict.rejected);
  });

  test(
    '17 mutually confirmed members form one group, excluding an outsider',
    () {
      final all = List.generate(18, (index) => index);
      final result = partitionConfirmed(all, (a, b) {
        return b < 17 || a == 0 ? PairVerdict.confirmed : PairVerdict.uncertain;
      }, maxChecks: 200);
      expect(result.exhausted, isFalse);
      expect(result.groups, [
        all.take(17).toList(),
        [17],
      ]);
    },
  );

  test('exhausted verification budget is explicit', () {
    final result = partitionConfirmed([0, 1, 2], (a, b) {
      return PairVerdict.confirmed;
    }, maxChecks: 1);
    expect(result.exhausted, isTrue);
    expect(result.groups, [
      [0, 1],
    ]);
  });
  test(
    'DINO candidates include visually similar pairs and separate screenshots',
    () {
      final candidates = findDinoCandidates(
        {
          0: [1.0, 0.0],
          1: [0.9, 0.1],
          2: [1.0, 0.0],
          3: [0.0, 1.0],
        },
        [false, false, true, false],
      );
      expect(candidates.length, 1);
      expect(candidates.single.first, 0);
      expect(candidates.single.second, 1);
    },
  );

  test('DINO candidates fail explicitly when the budget is exceeded', () {
    expect(
      () => findDinoCandidates(
        {
          0: [1.0],
          1: [1.0],
        },
        [false, false],
        maxPhotos: 1,
      ),
      throwsStateError,
    );
  });
}
