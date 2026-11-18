/// Chia một thành phần liên thông thành nhiều "sao": đại diện + các ảnh có độ giống
/// trực tiếp với đại diện >= [minCos]. Ảnh nào không vào sao đầu tiên không bị bỏ
/// rơi mà được xét lại với đại diện kế tiếp, nên một chuỗi ảnh chụp liên tiếp
/// không còn mất các khung nằm xa đại diện đầu tiên.
///
/// [ranked] đã sắp theo thứ tự ưu tiên làm đại diện (ảnh lớn nhất/cũ nhất trước).
/// [cos] trả về độ giống của hai ảnh (null/âm = không giống). [budget] giới hạn
/// tổng số lần gọi [cos] để thành phần rất lớn không tốn O(m²).
/// Đại diện không có ảnh đi cùng bị bỏ (ảnh đơn lẻ).
List<List<int>> starPartition(
  List<int> ranked,
  double? Function(int a, int b) cos,
  double minCos, {
  int budget = 3000000,
}) {
  final out = <List<int>>[];
  var rest = List<int>.of(ranked);
  var spent = 0;
  while (rest.length >= 2) {
    final rep = rest.first;
    final star = <int>[rep];
    final left = <int>[];
    for (var i = 1; i < rest.length; i++) {
      final m = rest[i];
      if ((cos(rep, m) ?? -1) >= minCos) {
        star.add(m);
      } else {
        left.add(m);
      }
    }
    spent += rest.length - 1;
    if (star.length >= 2) out.add(star);
    rest = left;
    if (spent >= budget) break;
  }
  return out;
}
