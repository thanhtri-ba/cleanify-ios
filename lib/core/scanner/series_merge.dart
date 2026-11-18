import 'dart:typed_data';

import '../../engines/dino/dino_matcher.dart';
import 'scan_session.dart';

/// Gộp nhóm "tương tự" vào nhóm "trùng" khi cùng một chuỗi ảnh chụp liên tiếp, để
/// một chuỗi chỉ hiện ở MỘT thẻ thay vì bị tách ra hai tab.
///
/// Với mỗi nhóm tương tự: chọn nhóm trùng có đại diện giống đại diện của nó nhất
/// (cosine >= [minCos]); chỉ gộp khi MỌI ảnh của nhóm tương tự đều có cosine >=
/// [minCos] với đại diện nhóm trùng đó. Ảnh gộp vào có `similarity == null` nên
/// "Dọn nhanh" không tự xóa. Không sửa nhóm tương tự (UI ẩn chúng qua
/// [similarExcludingDuplicates]). Trả về số nhóm tương tự đã gộp.
int mergeSimilarIntoDuplicates({
  required List<DuplicateGroup> dups,
  required List<DuplicateGroup> sims,
  required Float32List? Function(DuplicateItem) embOf,
  double minCos = kCosineSimilar,
  int maxPairs = 2000000,
}) {
  if (dups.isEmpty || sims.isEmpty) return 0;
  final dupReps = [for (final d in dups) embOf(d.items.first)];
  var merged = 0;
  var pairs = 0;
  for (final s in sims) {
    if (s.items.length < 2) continue;
    final sRep = embOf(s.items.first);
    if (sRep == null) continue;
    pairs += dups.length;
    if (pairs > maxPairs) break;
    var best = -1;
    var bestCos = minCos;
    for (var i = 0; i < dups.length; i++) {
      final c = cosineOf(sRep, dupReps[i]);
      if (c != null && c >= bestCos) {
        bestCos = c;
        best = i;
      }
    }
    if (best < 0) continue;
    final target = dups[best];
    final rep = dupReps[best];
    final cos = <double>[];
    var all = true;
    for (final e in s.items) {
      final c = cosineOf(embOf(e), rep);
      if (c == null || c < minCos) {
        all = false;
        break;
      }
      cos.add(c);
    }
    if (!all) continue;
    final have = {for (final e in target.items) e.asset.id};
    for (var k = 0; k < s.items.length; k++) {
      final e = s.items[k];
      if (have.add(e.asset.id)) {
        target.items.add(DuplicateItem(e.asset, exact: false, modelCosine: cos[k]));
      }
    }
    merged++;
  }
  return merged;
}
