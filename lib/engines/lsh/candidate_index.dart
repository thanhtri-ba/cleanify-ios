import 'dart:typed_data';

import '../pdq/pdq_engine.dart';

class MatchEdge {
  const MatchEdge(this.a, this.b, this.distance);
  final int a;
  final int b;
  final int distance;
}

/// LSH kiểu band: chia 256 bit thành 32 band x 8 bit. Hai ảnh là ứng viên nếu
/// trùng ít nhất một band.
///
/// Vì sao 8 bit chứ không phải 16 như trước: với ngưỡng Hamming 56 (78%), xác
/// suất MỘT band 16 bit khớp hẳn chỉ khoảng 2%, nên 16 band chỉ bắt được chừng
/// một phần tư số cặp — thư viện trên 6000 ảnh mất phần lớn ảnh "gần giống".
/// Band 8 bit khớp với xác suất khoảng 14%, 32 band bắt được trên 99% cặp ở
/// Hamming 56 và gần như đủ ở mọi khoảng cách thấp hơn. Đổi lại bucket đông hơn
/// (n/256 ảnh mỗi bucket), nên mỗi cặp chỉ được phát ra ở band ĐẦU TIÊN mà hai
/// ảnh khớp — không cần tập "đã thấy" khổng lồ trong RAM.
///
/// [flat]: 4 word/ảnh. [has]: 1 nếu ảnh có hash. Bucket quá lớn (ảnh trắng/đen
/// hoặc ảnh gần như đồng nhất) bị bỏ qua để tránh bùng nổ số cặp.
List<MatchEdge> findNearEdges({
  required Uint64List flat,
  required Uint8List has,
  required int n,
  required int maxHamming,
  int maxBucket = 1500,
  int exactBelow = 6000,
}) {
  final edges = <MatchEdge>[];
  // Thư viện không quá lớn: so mọi cặp, không bỏ sót cặp nào. ~18 triệu phép so
  // cho 6000 ảnh. Quá ngưỡng đó phép so bình phương đắt nhanh (30k ảnh ~450M
  // cặp) nên chuyển sang đường chỉ mục bên dưới.
  if (n <= exactBelow && n <= 6000) {
    for (var i = 0; i < n; i++) {
      if (has[i] == 0) continue;
      for (var j = i + 1; j < n; j++) {
        if (has[j] == 0) continue;
        final d = hammingFlat(flat, i, j);
        if (d <= maxHamming) edges.add(MatchEdge(i, j, d));
      }
    }
    return edges;
  }
  int key(int i, int band) =>
      (flat[i * 4 + (band >> 3)] >>> ((band & 7) * 8)) & 0xFF;
  for (var band = 0; band < 32; band++) {
    final buckets = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (has[i] == 0) continue;
      (buckets[key(i, band)] ??= <int>[]).add(i);
    }
    for (final bucket in buckets.values) {
      if (bucket.length < 2 || bucket.length > maxBucket) continue;
      for (var x = 0; x < bucket.length; x++) {
        for (var y = x + 1; y < bucket.length; y++) {
          final i = bucket[x];
          final j = bucket[y];
          final d = hammingFlat(flat, i, j);
          if (d > maxHamming) continue;
          // Đã phát ra ở một band trước đó thì bỏ.
          var dup = false;
          for (var b = 0; b < band; b++) {
            if (key(i, b) == key(j, b)) {
              dup = true;
              break;
            }
          }
          if (!dup) edges.add(MatchEdge(i, j, d));
        }
      }
    }
  }
  return edges;
}

class UnionFind {
  UnionFind(int n) : _p = List<int>.generate(n, (i) => i);
  final List<int> _p;

  int find(int x) {
    while (_p[x] != x) {
      _p[x] = _p[_p[x]];
      x = _p[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) _p[rb] = ra;
  }
}
