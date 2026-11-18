import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleanify/core/scanner/scan_session.dart';
import 'package:cleanify/core/scanner/series_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _a(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 100, height: 100);

Float32List _v(double deg) {
  final r = deg * math.pi / 180;
  return Float32List.fromList([math.cos(r), math.sin(r), 0]);
}

DuplicateItem _it(String id) => DuplicateItem(_a(id), exact: false, similarity: 100);

void main() {
  final angle = <String, double>{'d1': 0, 'd2': 3, 's1': 8, 's2': 12, 'far': 70};
  Float32List? emb(DuplicateItem it) {
    final a = angle[it.asset.id];
    return a == null ? null : _v(a);
  }

  test('gộp nhóm tương tự cùng chuỗi vào nhóm trùng, similarity null', () {
    final dup = DuplicateGroup([_it('d1'), _it('d2')]);
    final sim = DuplicateGroup([_it('s1'), _it('s2')], kind: GroupKind.similar);
    final n = mergeSimilarIntoDuplicates(dups: [dup], sims: [sim], embOf: emb);
    expect(n, 1);
    expect([for (final e in dup.items) e.asset.id], ['d1', 'd2', 's1', 's2']);
    expect(dup.items.last.similarity, isNull);
  });

  test('không gộp khi có ảnh lệch xa', () {
    final dup = DuplicateGroup([_it('d1'), _it('d2')]);
    final sim = DuplicateGroup([_it('s1'), _it('far')], kind: GroupKind.similar);
    expect(mergeSimilarIntoDuplicates(dups: [dup], sims: [sim], embOf: emb), 0);
    expect(dup.items.length, 2);
  });

  test('không có nhóm trùng thì trả 0', () {
    final sim = DuplicateGroup([_it('s1'), _it('s2')], kind: GroupKind.similar);
    expect(mergeSimilarIntoDuplicates(dups: [], sims: [sim], embOf: emb), 0);
  });
}
