import 'package:cleanify/core/scanner/star_groups.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 0-1-2 giống nhau; 3 chỉ giống 2 (xa đại diện 0); 4 lẻ loi.
  double? cos(int a, int b) {
    const close = {'0,1', '0,2', '1,2', '2,3'};
    final k = a < b ? '$a,$b' : '$b,$a';
    return close.contains(k) ? 0.9 : 0.1;
  }

  test('đại diện đầu gom đúng ảnh giống trực tiếp, ảnh lẻ không vào nhóm', () {
    final r = starPartition([0, 1, 2, 3, 4], cos, 0.7);
    expect(r.first, [0, 1, 2]);
    expect(r.expand((e) => e).contains(4), isFalse);
  });

  test('không có cặp nào thì trả rỗng', () {
    expect(starPartition([0, 4], cos, 0.7), isEmpty);
  });

  test('ngân sách chặn việc quét tiếp', () {
    final r = starPartition([0, 1, 2, 3, 4], cos, 0.7, budget: 1);
    expect(r.length, lessThanOrEqualTo(1));
  });
}
