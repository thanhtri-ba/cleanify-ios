/// Conservative reconciliation for partitions split from one similarity
/// component. It requires repeated evidence across groups and complete-link
/// support across every original partition, so a single bridge cannot chain
/// unrelated groups together.
bool nearDuplicatePairEvidence({
  required int? hamming,
  required bool? pdqQualityOk,
  required double? centeredCosine,
  required int maxHamming,
  required int similarMaxHamming,
  required double modelMinCosine,
}) {
  if (hamming == null || pdqQualityOk != true) return false;
  return hamming <= maxHamming ||
      (hamming <= similarMaxHamming &&
          (centeredCosine ?? -1) >= modelMinCosine);
}

bool burstLikePairEvidence({
  required int gapMs,
  required double? rawCosine,
  required int burstWindowMs,
  required double burstMinRawCosine,
}) => gapMs.abs() <= burstWindowMs && (rawCosine ?? -1) >= burstMinRawCosine;

List<List<int>> reconcileSimilarPartitions({
  required List<List<int>> partitions,
  required bool Function(int a, int b) matches,
  required int Function(int a, int b) gapMs,
  int minIndependentPairs = 2,
  int maxPairChecks = 200000,
}) {
  if (partitions.length < 2) {
    return partitions.map(List<int>.of).toList(growable: false);
  }

  var checks = 0;
  final supported = List.generate(
    partitions.length,
    (_) => List<bool>.filled(partitions.length, false),
  );
  final supportCount = List.generate(
    partitions.length,
    (_) => List<int>.filled(partitions.length, 0),
  );
  final nearestGap = List.generate(
    partitions.length,
    (_) => List<int>.filled(partitions.length, 1 << 62),
  );

  for (var i = 0; i < partitions.length; i++) {
    for (var j = i + 1; j < partitions.length; j++) {
      final left = partitions[i];
      final right = partitions[j];
      if (left.length * right.length > maxPairChecks - checks) {
        // Missing or excessive evidence must never trigger a merge.
        return partitions.map(List<int>.of).toList(growable: false);
      }
      final coveredLeft = <int>{};
      final coveredRight = <int>{};
      var hits = 0;
      var minGap = 1 << 62;
      for (final a in left) {
        for (final b in right) {
          checks++;
          final gap = gapMs(a, b).abs();
          if (gap < minGap) minGap = gap;
          if (matches(a, b)) {
            hits++;
            coveredLeft.add(a);
            coveredRight.add(b);
          }
        }
      }
      supportCount[i][j] = hits;
      nearestGap[i][j] = minGap;
      final minLeftCoverage = left.length <= right.length
          ? left.length
          : minIndependentPairs;
      final minRightCoverage = right.length <= left.length
          ? right.length
          : minIndependentPairs;
      supported[i][j] =
          hits >= minIndependentPairs &&
          coveredLeft.length >= minLeftCoverage &&
          coveredRight.length >= minRightCoverage;
    }
  }

  int pairGap(int a, int b) => a < b ? nearestGap[a][b] : nearestGap[b][a];
  int pairSupport(int a, int b) =>
      a < b ? supportCount[a][b] : supportCount[b][a];
  bool pairSupported(int a, int b) => a < b ? supported[a][b] : supported[b][a];

  var clusters = [
    for (var i = 0; i < partitions.length; i++) <int>[i],
  ];
  while (true) {
    var bestA = -1;
    var bestB = -1;
    var bestGap = 1 << 62;
    var bestSupport = -1;
    for (var i = 0; i < clusters.length; i++) {
      for (var j = i + 1; j < clusters.length; j++) {
        var completeLink = true;
        var maxGap = 0;
        var weakestSupport = 1 << 62;
        for (final a in clusters[i]) {
          for (final b in clusters[j]) {
            if (!pairSupported(a, b)) {
              completeLink = false;
              break;
            }
            final g = pairGap(a, b);
            if (g > maxGap) maxGap = g;
            final n = pairSupport(a, b);
            if (n < weakestSupport) weakestSupport = n;
          }
          if (!completeLink) break;
        }
        if (!completeLink) continue;
        // Prefer groups captured closer together, then stronger cross support.
        if (maxGap < bestGap ||
            (maxGap == bestGap && weakestSupport > bestSupport)) {
          bestA = i;
          bestB = j;
          bestGap = maxGap;
          bestSupport = weakestSupport;
        }
      }
    }
    if (bestA < 0) break;
    clusters[bestA] = [...clusters[bestA], ...clusters[bestB]]..sort();
    clusters.removeAt(bestB);
  }

  return [
    for (final cluster in clusters) [for (final p in cluster) ...partitions[p]],
  ];
}
