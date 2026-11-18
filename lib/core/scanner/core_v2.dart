/// Internal rollout mode selected at build time. Default is V2 active.
enum CoreMode {
  v1Only,
  v2Shadow,
  v2Active,
  v2Disabled;

  static CoreMode parse(String value) => switch (value) {
    'V1_ONLY' => CoreMode.v1Only,
    'V2_SHADOW' => CoreMode.v2Shadow,
    'V2_ACTIVE' => CoreMode.v2Active,
    'V2_DISABLED' => CoreMode.v2Disabled,
    // Mặc định là V2: lõi mới chạy thật, không chỉ chạy bóng.
    // Quay về lõi cũ bằng --dart-define=CLEANIFY_CORE=V1_ONLY.
    _ => CoreMode.v2Active,
  };
}

enum PairVerdict { confirmed, rejected, uncertain }

/// Thresholds are provisional until calibrated on labeled device data.
PairVerdict verifyNearPair({
  required bool sameCaptureType,
  required int? hamming,
  required double? cosine,
  required int maxHamming,
  required int candidateHamming,
  required double minCosine,
}) {
  if (!sameCaptureType) return PairVerdict.rejected;
  if (hamming == null || cosine == null || !cosine.isFinite) {
    return PairVerdict.uncertain;
  }
  if (hamming <= maxHamming && cosine >= minCosine) {
    return PairVerdict.confirmed;
  }
  if (hamming > candidateHamming && cosine < minCosine) {
    return PairVerdict.rejected;
  }
  return PairVerdict.uncertain;
}

typedef CorePartition = ({List<List<int>> groups, bool exhausted});

/// Makes disjoint groups in keeper order. Every pair in a group must be
/// confirmed. A work limit keeps large candidate components bounded.
CorePartition partitionConfirmed(
  List<int> ranked,
  PairVerdict Function(int, int) verify, {
  required int maxChecks,
}) {
  final groups = <List<int>>[];
  var checks = 0;
  for (final member in ranked) {
    List<int>? destination;
    for (final group in groups) {
      var confirmed = true;
      for (final peer in group) {
        if (checks >= maxChecks) return (groups: groups, exhausted: true);
        checks++;
        if (verify(peer, member) == PairVerdict.confirmed) continue;
        confirmed = false;
        break;
      }
      if (confirmed) {
        destination = group;
        break;
      }
    }
    if (destination == null) {
      groups.add([member]);
    } else {
      destination.add(member);
    }
  }
  return (groups: groups, exhausted: false);
}

/// Candidate edges for an experimental DINOv2 shadow scan. Similarity is a
/// retrieval signal and these edges do not by themselves establish a group.
class DinoCandidate {
  const DinoCandidate(this.first, this.second, this.cosine);
  final int first;
  final int second;
  final double cosine;
}

List<DinoCandidate> findDinoCandidates(
  Map<int, List<double>> vectors,
  List<bool> screenshots, {
  double floor = 0.50,
  int maxPhotos = 2000,
  int maxNeighbors = 80,
}) {
  if (vectors.length > maxPhotos) {
    throw StateError('DINOv2 shadow scan exceeds candidate budget');
  }
  final ids = vectors.keys.toList()..sort();
  final edges = <DinoCandidate>[];
  for (var i = 0; i < ids.length; i++) {
    final a = ids[i];
    final matches = <DinoCandidate>[];
    for (var j = i + 1; j < ids.length; j++) {
      final b = ids[j];
      if (screenshots[a] != screenshots[b]) continue;
      final left = vectors[a];
      final right = vectors[b];
      if (left == null || right == null || left.length != right.length) {
        continue;
      }
      var cosine = 0.0;
      for (var k = 0; k < left.length; k++) {
        cosine += left[k] * right[k];
      }
      if (cosine.isFinite && cosine >= floor) {
        matches.add(DinoCandidate(a, b, cosine));
      }
    }
    matches.sort((a, b) => b.cosine.compareTo(a.cosine));
    edges.addAll(matches.take(maxNeighbors));
  }
  return edges;
}
