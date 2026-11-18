import 'package:cleanify/core/scanner/cross_group_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

CrossGroupPairEvidence _pair(
  String a,
  String b,
  String left,
  String right, {
  int? h = 10,
  bool? quality = true,
  double? centered = 0.9,
  double? raw = 0.9,
  int gap = 1000,
}) => CrossGroupPairEvidence(
  groupA: a,
  groupB: b,
  assetA: left,
  assetB: right,
  gapMs: gap,
  hamming: h,
  qualityOk: quality,
  centeredCosine: centered,
  rawCosine: raw,
);

String _run(
  List<CrossGroupPairEvidence> pairs, {
  Map<String, int> sizes = const {'A': 6, 'B': 3, 'C': 2},
}) => crossGroupDryRun(
  pairs: pairs,
  groupSizes: sizes,
  maxHamming: 32,
  similarMaxHamming: 64,
  modelMinCosine: 0.8,
  burstWindowMs: 15000,
  burstMinRawCosine: 0.7,
);

void main() {
  test(
    'near-duplicate needs independent cross pairs and coverage on both sides',
    () {
      final report = _run([
        _pair('A', 'B', 'a1', 'b1'),
        _pair('A', 'B', 'a2', 'b2'),
      ]);
      expect(report, contains('Near-duplicate: PASS'));
      expect(report, contains('2 cặp đạt'));
      expect(report, contains('chỉ đọc, không tự gộp'));
    },
  );

  // Synthetic feature measurements only; these labels do not represent the
  // user's original assets, which have not been supplied to the workspace.
  test('labeled report for the reported group 3 + 4 case', () {
    final report = _run(
      [
        _pair('Nhóm 3', 'Nhóm 4', 'g3-1', 'g4-1'),
        _pair('Nhóm 3', 'Nhóm 4', 'g3-2', 'g4-2'),
      ],
      sizes: const {'Nhóm 3': 6, 'Nhóm 4': 3},
    );
    expect(report, contains('Nhóm 3 ↔ Nhóm 4'));
    expect(report, contains('Near-duplicate: PASS'));
  });

  test('reported groups 37–39 are assessed pairwise, without chain merge', () {
    final report = _run(
      [
        _pair('Nhóm 37', 'Nhóm 38', 'g37-1', 'g38-1'),
        _pair('Nhóm 37', 'Nhóm 38', 'g37-2', 'g38-2'),
        _pair('Nhóm 38', 'Nhóm 39', 'g38-1', 'g39-1'),
        _pair('Nhóm 38', 'Nhóm 39', 'g38-2', 'g39-2'),
      ],
      sizes: const {'Nhóm 37': 2, 'Nhóm 38': 2, 'Nhóm 39': 2},
    );
    expect(report, contains('Nhóm 37 ↔ Nhóm 38'));
    expect(report, contains('Nhóm 38 ↔ Nhóm 39'));
    expect(report, isNot(contains('Nhóm 37 ↔ Nhóm 39')));
  });

  test('labeled report for the reported group 32 + 33 case', () {
    final report = _run(
      [
        _pair('Nhóm 32', 'Nhóm 33', 'g32-1', 'g33-1'),
        _pair('Nhóm 32', 'Nhóm 33', 'g32-2', 'g33-2'),
      ],
      sizes: const {'Nhóm 32': 2, 'Nhóm 33': 2},
    );
    expect(report, contains('Nhóm 32 ↔ Nhóm 33'));
    expect(report, contains('Near-duplicate: PASS'));
  });

  test('one repeated edge cannot suggest merging whole groups', () {
    final report = _run([
      _pair('A', 'B', 'a1', 'b1'),
      _pair('B', 'A', 'b1', 'a1'),
    ]);
    expect(report, contains('Near-duplicate: FAIL'));
  });

  test('burst-like has its own time and raw cosine conditions', () {
    final report = _run([
      _pair('A', 'B', 'a1', 'b1', h: 90, gap: 900),
      _pair('A', 'B', 'a2', 'b2', h: 100, gap: 14000),
    ]);
    expect(report, contains('Near-duplicate: FAIL'));
    expect(report, contains('Burst-like: PASS'));
  });

  test('missing features produce UNKNOWN rather than a merge suggestion', () {
    final report = _run([
      _pair(
        'A',
        'B',
        'a1',
        'b1',
        h: null,
        quality: null,
        centered: null,
        raw: null,
      ),
      _pair(
        'A',
        'B',
        'a2',
        'b2',
        h: null,
        quality: null,
        centered: null,
        raw: null,
      ),
    ]);
    expect(report, contains('Near-duplicate: UNKNOWN'));
    expect(report, contains('Burst-like: UNKNOWN'));
  });

  test('unrelated content does not pass either class', () {
    final report = _run([
      _pair('A', 'B', 'a1', 'b1', h: 120, centered: 0.1, raw: 0.2, gap: 30000),
      _pair(
        'A',
        'B',
        'a2',
        'b2',
        h: 130,
        centered: 0.15,
        raw: 0.25,
        gap: 40000,
      ),
    ]);
    expect(report, contains('Near-duplicate: FAIL'));
    expect(report, contains('Burst-like: FAIL'));
  });

  test('pair and group ordering does not change the report', () {
    final pairs = [_pair('B', 'A', 'b1', 'a1'), _pair('A', 'B', 'a2', 'b2')];
    expect(_run(pairs), _run(pairs.reversed.toList()));
  });
}
