import 'package:cleanify/core/scanner/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _a(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 100, height: 100);

DuplicateItem _rep(String id) =>
    DuplicateItem(_a(id), exact: false, similarity: 100);

DuplicateItem _m(String id, double cos, {int? h}) =>
    DuplicateItem(_a(id), exact: false, modelCosine: cos, pdqHamming: h);

void main() {
  final g = DuplicateGroup([
    _rep('r'),
    _m('a', 0.82),
    _m('b', 0.70),
    _m('c', 0.62),
  ], kind: GroupKind.similar);

  List<String> ids(SimilarLevel l) => [
        for (final x in similarExcludingDuplicates([g], level: l))
          for (final e in x.items) e.asset.id
      ];

  test('mỗi mức giữ đúng ảnh có cosine >= mức đó', () {
    // Dải độ lệch mới: Chặt >= 80%, Vừa >= 65%, Rộng >= 50% (dưới 50% thì không nhận).
    expect(SimilarLevel.strict.percent, 80);
    expect(SimilarLevel.normal.percent, 65);
    expect(SimilarLevel.wide.percent, 50);
    expect(ids(SimilarLevel.strict), ['r', 'a']);
    expect(ids(SimilarLevel.normal), ['r', 'a', 'b']);
    expect(ids(SimilarLevel.wide), ['r', 'a', 'b', 'c']);
  });

  test('mặc định là mức Vừa', () {
    expect(similarExcludingDuplicates([g]).single.items.length, 3);
  });

  test('còn dưới 2 ảnh thì bỏ nhóm', () {
    final g2 =
        DuplicateGroup([_rep('r'), _m('c', 0.62)], kind: GroupKind.similar);
    expect(
        similarExcludingDuplicates([g2], level: SimilarLevel.normal), isEmpty);
  });

  test('Hamming PDQ quá lớn thì bị ẩn khi cosine chưa đủ cao', () {
    // Cosine 0,70 < mức Chặt (0,80): PDQ vẫn có quyền loại ảnh quá khác hình dạng.
    final g3 = DuplicateGroup(
        [_rep('r'), _m('x', 0.70, h: 115), _m('y', 0.70, h: 40)],
        kind: GroupKind.similar);
    List<String> at(SimilarLevel l) => [
          for (final e in similarExcludingDuplicates([g3], level: l)
              .expand((x) => x.items))
            e.asset.id
        ];
    expect(at(SimilarLevel.strict),
        isEmpty); // cả hai cosine 0,70 < 0,80: chỉ còn ảnh đại diện nên nhóm bị bỏ
    expect(at(SimilarLevel.normal), ['r', 'y']);
    expect(at(SimilarLevel.wide), ['r', 'x', 'y']);
  });

  test('cosine cao (>= mức Chặt) thì Hamming PDQ lớn vẫn không loại ảnh', () {
    final g4 = DuplicateGroup(
        [_rep('r'), _m('z', 0.90, h: 119), _m('w', 0.70, h: 119)],
        kind: GroupKind.similar);
    List<String> at(SimilarLevel l) => [
          for (final e in similarExcludingDuplicates([g4], level: l)
              .expand((x) => x.items))
            e.asset.id
        ];
    // z: cosine 0,90 >= 0,80 nên giữ dù Hamming 119 > 96. w: cosine thấp nên vẫn bị PDQ loại ở mức Chặt/Vừa.
    expect(at(SimilarLevel.strict), ['r', 'z']);
    expect(at(SimilarLevel.normal), ['r', 'z']);
    expect(at(SimilarLevel.wide), ['r', 'z', 'w']);
  });

  test('thanh kéo: minCosine tùy ý lọc đúng ảnh', () {
    List<String> at(double c) => [
          for (final x in similarExcludingDuplicates([g], minCosine: c))
            for (final e in x.items) e.asset.id
        ];
    expect(at(0.84), isEmpty); // chỉ còn ảnh đại diện nên nhóm bị bỏ
    expect(at(0.75), ['r', 'a']);
    expect(at(0.64), ['r', 'a', 'b']);
    expect(at(0.50), ['r', 'a', 'b', 'c']);
    // Dưới 50% (cosine < 0,50) không nhận ở bất kỳ mức nào.
    final far =
        DuplicateGroup([_rep('r'), _m('f', 0.45)], kind: GroupKind.similar);
    expect(
        similarExcludingDuplicates([far], level: SimilarLevel.wide), isEmpty);
  });

  test('Hamming nội suy theo cosine, kẹp ở hai đầu', () {
    expect(hammingForCosine(0.40), SimilarLevel.wide.maxHamming);
    expect(hammingForCosine(0.90), SimilarLevel.strict.maxHamming);
    final mid = hammingForCosine(0.65);
    expect(
        mid,
        inInclusiveRange(
            SimilarLevel.strict.maxHamming, SimilarLevel.wide.maxHamming));
  });
}
