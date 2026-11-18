import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart';

import '../../engines/dino/dino_engine.dart';

/// Chữ ký MediaStore của một ảnh: dung lượng và thế hệ (xem PhotoEdits.signatures).
typedef MediaSig = ({int size, int gen});

/// Vân tay PDQ đã nhớ của một ảnh.
class PdqRow {
  const PdqRow({required this.quality, required this.pdq});

  /// Điểm chất lượng PDQ 0-100.
  final int quality;

  /// 4 word 64-bit.
  final Uint64List pdq;
}

/// Kho nhớ giữa các lần quét, một file SQLite trong bộ nhớ riêng của app.
///
/// Mỗi ảnh một dòng, khoá là MediaStore `_ID`:
///  - vân tay PDQ (32 byte) và điểm chất lượng;
///  - chữ ký MediaStore: dung lượng và thế hệ;
///  - SHA-256 (32 byte), chỉ khi ảnh đã từng cần;
///  - vector embedding của mô hình (dinoDim byte, int8), chỉ khi đã từng nhúng.
///
/// Mọi giá trị đều là số một chiều: không dựng lại được ảnh. Không lưu nhóm
/// trùng hay kết quả quét nào.
///
/// Vì sao không dùng MediaStore để lưu: MediaStore chỉ chứa metadata của ảnh,
/// không cho app lưu dữ liệu riêng. Khoá bằng `_ID` + thế hệ là đủ để biết dòng
/// nào còn đúng với ảnh hiện tại.
///
/// Đọc theo lô 400 id, không nạp cả thư viện vào RAM.
class PhotoStore {
  PhotoStore._();

  /// Tăng MỖI KHI cách băm PDQ hoặc định dạng đổi. Khác phiên bản thì bỏ hết
  /// dòng, vì vân tay cũ không so với vân tay mới được.
  static const int pdqVersion = 5;

  /// Tăng MỖI KHI mô hình hoặc cách lượng tử hoá đổi. Khác phiên bản thì chỉ bỏ
  /// embedding, vân tay PDQ vẫn dùng được.
  static const int embVersion = 1;

  static const String _dbName = 'cleanify_photos.db';

  /// Giữ tên file cờ cũ để công tắc người dùng đã chọn không bị reset.
  static const String _flagName = 'pdq_cache_on.txt';

  /// File của các bản trước, xoá khi mở kho mới.
  static const List<String> _legacy = [
    'pdq_cache.bin',
    'pdq_cache.bin.tmp',
    'cleanify_emb.db',
  ];

  /// Người dùng đã bật ghi nhớ chưa. Bật mặc định để các lần quét sau nhanh hơn.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static Future<Database?>? _opening;

  static Future<void> loadFlag() async {
    try {
      final f = await _at(_flagName);
      if (f == null || !await f.exists()) return;
      enabled.value = (await f.readAsString()).trim() == '1';
    } catch (_) {}
  }

  /// Bật/tắt. Tắt thì xoá luôn kho, không để lại gì.
  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    try {
      final f = await _at(_flagName);
      await f?.writeAsString(on ? '1' : '0');
    } catch (_) {}
    if (!on) await clear();
  }

  /// Xoá sạch kho, đóng kết nối, xoá cả file của các bản trước.
  static Future<void> clear() async {
    final pending = _opening;
    _opening = null;
    try {
      (await pending)?.close();
    } catch (_) {}
    try {
      final dir = await getApplicationSupportDirectory();
      for (final name in [
        _dbName,
        '$_dbName-journal',
        '$_dbName-wal',
        '$_dbName-shm',
        ..._legacy,
      ]) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  static Future<File?> _at(String name) async {
    try {
      final d = await getApplicationSupportDirectory();
      return File(p.join(d.path, name));
    } catch (_) {
      return null;
    }
  }

  /// Mở kho một lần; null khi đã tắt hoặc không mở được.
  static Future<Database?> _open() async {
    if (!enabled.value) return null;
    final db = await (_opening ??= _doOpen());
    if (db == null) _opening = null; // lần sau thử lại
    return db;
  }

  static Future<Database?> _doOpen() async {
    try {
      final dir = await getApplicationSupportDirectory();
      for (final name in _legacy) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) await f.delete();
      }
      final db = await openDatabase(
        p.join(dir.path, _dbName),
        version: 1,
        onCreate: (d, _) async {
          await d.execute(
            'CREATE TABLE photo('
            'id TEXT PRIMARY KEY, modified INTEGER NOT NULL, '
            'created INTEGER NOT NULL, w INTEGER NOT NULL, h INTEGER NOT NULL, '
            'quality INTEGER NOT NULL, pdq BLOB NOT NULL, '
            'size INTEGER NOT NULL, gen INTEGER NOT NULL, '
            'sha BLOB, emb BLOB)',
          );
          await d.execute(
            'CREATE TABLE meta(k TEXT PRIMARY KEY, v INTEGER NOT NULL)',
          );
        },
      );
      if (await _meta(db, 'pdq') != pdqVersion) {
        await db.delete('photo');
        await _setMeta(db, 'pdq', pdqVersion);
      }
      if (await _meta(db, 'emb') != embVersion) {
        await db.update('photo', {'emb': null});
        await _setMeta(db, 'emb', embVersion);
      }
      return db;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _meta(Database db, String k) async {
    final r = await db.query('meta', columns: ['v'], where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as int;
  }

  static Future<void> _setMeta(Database db, String k, int v) =>
      db.insert('meta', {'k': k, 'v': v},
          conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------------------------------------------------------------------------
  // Khớp còn nguyên hay không.

  /// Dòng còn đúng với ảnh [a] không. Phải khớp CẢ ngày sửa, ngày chụp, rộng,
  /// cao, và chữ ký MediaStore nếu có. Chỉ dựa vào ngày sửa là không đủ: một
  /// ảnh bị chỉnh mà ngày sửa không đổi sẽ dùng vân tay cũ, gom nhầm, rồi xoá
  /// nhầm bản mình vừa sửa.
  static bool _matches(
    AssetEntity a,
    MediaSig? sig, {
    required int modified,
    required int created,
    required int w,
    required int h,
    required int size,
    required int gen,
  }) {
    final m = a.modifiedDateSecond;
    if (m == null || m == 0 || m != modified) return false;
    if (a.createDateTime.millisecondsSinceEpoch ~/ 1000 != created) return false;
    if (a.width != w || a.height != h) return false;
    if (sig != null && size > 0 && (sig.size != size || sig.gen != gen)) {
      return false;
    }
    return true;
  }

  /// Đọc cột theo lô 400 id (SQLite chỉ nhận khoảng 999 tham số buộc).
  static Future<List<Map<String, Object?>>> _rows(
    Database db,
    List<AssetEntity> assets,
    String cols,
  ) async {
    final out = <Map<String, Object?>>[];
    final ids = [for (final a in assets) a.id];
    for (var s = 0; s < ids.length; s += 400) {
      final part = ids.sublist(s, math.min(s + 400, ids.length));
      final holes = List.filled(part.length, '?').join(',');
      out.addAll(await db.rawQuery(
        'SELECT id, $cols FROM photo WHERE id IN ($holes)',
        part,
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Vân tay PDQ.

  /// Vân tay PDQ còn đúng của các ảnh trong [batch], theo id.
  static Future<Map<String, PdqRow>> pdqFor(
    List<AssetEntity> batch,
    Map<String, MediaSig> sigs,
  ) async {
    final db = await _open();
    if (db == null || batch.isEmpty) return {};
    final byId = {for (final a in batch) a.id: a};
    final out = <String, PdqRow>{};
    try {
      final rows = await _rows(
        db,
        batch,
        'modified, created, w, h, quality, pdq, size, gen',
      );
      for (final r in rows) {
        final id = r['id'] as String;
        final a = byId[id];
        final blob = r['pdq'];
        if (a == null || blob is! Uint8List || blob.length != 32) continue;
        if (!_matches(
          a,
          sigs[id],
          modified: r['modified'] as int,
          created: r['created'] as int,
          w: r['w'] as int,
          h: r['h'] as int,
          size: r['size'] as int,
          gen: r['gen'] as int,
        )) {
          continue;
        }
        final bd = ByteData.sublistView(blob);
        final pdq = Uint64List(4);
        for (var k = 0; k < 4; k++) {
          pdq[k] = bd.getUint64(k * 8, Endian.little);
        }
        out[id] = PdqRow(quality: r['quality'] as int, pdq: pdq);
      }
    } catch (_) {}
    return out;
  }

  /// Ghi vân tay của các ảnh vừa băm (không ghi ảnh đã dùng lại). Khi ảnh đã
  /// đổi, SHA và embedding cũ bị xoá để không dùng nhầm.
  static Future<void> savePdq(
    List<AssetEntity> assets,
    Uint64List flat,
    Uint8List quality,
    Uint8List hashed,
    Uint8List reused,
    Map<String, MediaSig> sigs,
  ) async {
    final db = await _open();
    if (db == null) return;
    try {
      final batch = db.batch();
      var any = false;
      for (var i = 0; i < assets.length; i++) {
        if (hashed[i] == 0 || reused[i] == 1) continue;
        final a = assets[i];
        final m = a.modifiedDateSecond;
        if (m == null || m == 0 || a.width <= 0 || a.height <= 0) continue;
        final sig = sigs[a.id];
        final bd = ByteData(32);
        for (var k = 0; k < 4; k++) {
          bd.setUint64(k * 8, flat[i * 4 + k], Endian.little);
        }
        batch.rawInsert(_upsertSql(), [
          a.id,
          m,
          a.createDateTime.millisecondsSinceEpoch ~/ 1000,
          a.width,
          a.height,
          quality[i],
          bd.buffer.asUint8List(),
          sig?.size ?? 0,
          sig?.gen ?? 0,
        ]);
        any = true;
      }
      if (any) await batch.commit(noResult: true);
    } catch (_) {
      // Không ghi được thì lần sau băm lại, không ảnh hưởng kết quả.
    }
  }

  /// Thêm dòng mới, hoặc cập nhật dòng cũ. Nếu ảnh đã đổi thì SHA và embedding
  /// của dòng cũ bị đặt về NULL.
  static String _upsertSql() {
    const same = 'photo.modified IS excluded.modified '
        'AND photo.created IS excluded.created '
        'AND photo.w IS excluded.w AND photo.h IS excluded.h '
        'AND photo.size IS excluded.size AND photo.gen IS excluded.gen';
    return 'INSERT INTO photo(id, modified, created, w, h, quality, pdq, size, gen, sha, emb) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL) '
        'ON CONFLICT(id) DO UPDATE SET '
        'sha = CASE WHEN $same THEN photo.sha ELSE NULL END, '
        'emb = CASE WHEN $same THEN photo.emb ELSE NULL END, '
        'modified = excluded.modified, created = excluded.created, '
        'w = excluded.w, h = excluded.h, quality = excluded.quality, '
        'pdq = excluded.pdq, size = excluded.size, gen = excluded.gen';
  }

  // ---------------------------------------------------------------------------
  // SHA-256.

  /// SHA-256 (hex) đã nhớ của các ảnh còn nguyên trong [batch].
  static Future<Map<String, String>> shaFor(
    List<AssetEntity> batch,
    Map<String, MediaSig> sigs,
  ) async {
    final db = await _open();
    if (db == null || batch.isEmpty) return {};
    final byId = {for (final a in batch) a.id: a};
    final out = <String, String>{};
    try {
      final rows = await _rows(db, batch, 'modified, created, w, h, size, gen, sha');
      for (final r in rows) {
        final id = r['id'] as String;
        final a = byId[id];
        final blob = r['sha'];
        if (a == null || blob is! Uint8List || blob.length != 32) continue;
        if (!_matches(
          a,
          sigs[id],
          modified: r['modified'] as int,
          created: r['created'] as int,
          w: r['w'] as int,
          h: r['h'] as int,
          size: r['size'] as int,
          gen: r['gen'] as int,
        )) {
          continue;
        }
        out[id] = hexOf(blob);
      }
    } catch (_) {}
    return out;
  }

  /// Ghi SHA-256 vừa tính cho các chỉ số [idx].
  static Future<void> saveSha(
    List<AssetEntity> assets,
    List<String?> shas,
    List<int> idx,
  ) async {
    final db = await _open();
    if (db == null || idx.isEmpty) return;
    try {
      final batch = db.batch();
      var any = false;
      for (final i in idx) {
        final h = unhex(shas[i]);
        if (h == null) continue;
        batch.rawUpdate(
          'UPDATE photo SET sha = ? WHERE id = ?',
          [h, assets[i].id],
        );
        any = true;
      }
      if (any) await batch.commit(noResult: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Embedding của mô hình.

  /// Embedding đã nhớ của các ảnh còn nguyên trong [batch], theo id.
  static Future<Map<String, Float32List>> embFor(
    List<AssetEntity> batch,
    Map<String, MediaSig> sigs,
  ) async {
    final db = await _open();
    if (db == null || batch.isEmpty) return {};
    final byId = {for (final a in batch) a.id: a};
    final out = <String, Float32List>{};
    try {
      final rows = await _rows(
        db,
        batch,
        'modified, created, w, h, size, gen, emb',
      );
      for (final r in rows) {
        final id = r['id'] as String;
        final a = byId[id];
        final blob = r['emb'];
        if (a == null || blob is! Uint8List || blob.length != dinoDim) continue;
        if (!_matches(
          a,
          sigs[id],
          modified: r['modified'] as int,
          created: r['created'] as int,
          w: r['w'] as int,
          h: r['h'] as int,
          size: r['size'] as int,
          gen: r['gen'] as int,
        )) {
          continue;
        }
        out[id] = _decode(blob);
      }
    } catch (_) {}
    return out;
  }

  /// Ghi embedding vừa nhúng. [raw] theo chỉ số trong [assets].
  static Future<void> saveEmb(
    List<AssetEntity> assets,
    Map<int, Float32List> raw,
  ) async {
    final db = await _open();
    if (db == null || raw.isEmpty) return;
    try {
      final batch = db.batch();
      var any = false;
      raw.forEach((i, v) {
        if (i < 0 || i >= assets.length || v.length != dinoDim) return;
        batch.rawUpdate(
          'UPDATE photo SET emb = ? WHERE id = ?',
          [_encode(v), assets[i].id],
        );
        any = true;
      });
      if (any) await batch.commit(noResult: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Dọn.

  /// Bỏ các dòng của ảnh đã xoá khỏi máy. Chỉ gọi khi đã đọc HẾT thư viện: nếu
  /// lần quét bị cắt giữa chừng thì phần chưa đọc vẫn còn là ảnh thật.
  static Future<void> prune(List<AssetEntity> assets) async {
    final db = await _open();
    if (db == null) return;
    try {
      await db.execute('CREATE TEMP TABLE IF NOT EXISTS live(id TEXT PRIMARY KEY)');
      await db.delete('live');
      final batch = db.batch();
      for (final a in assets) {
        batch.rawInsert('INSERT OR IGNORE INTO live(id) VALUES (?)', [a.id]);
      }
      await batch.commit(noResult: true);
      await db.execute('DELETE FROM photo WHERE id NOT IN (SELECT id FROM live)');
      await db.delete('live');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Mã hoá.

  /// SHA-256 dạng hex -> 32 byte; null nếu không đúng dạng.
  static Uint8List? unhex(String? h) {
    if (h == null || h.length != 64) return null;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      final v = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
      if (v == null) return null;
      out[i] = v;
    }
    return out;
  }

  /// Byte -> hex thường, cùng dạng mà kênh native trả về.
  static String hexOf(Uint8List b) {
    final sb = StringBuffer();
    for (final v in b) {
      if (v < 0x10) sb.write('0');
      sb.write(v.toRadixString(16));
    }
    return sb.toString();
  }

  /// L2-normalize -> int8. Đầu ra mô hình đã chuẩn hoá nên nằm trong [-1, 1].
  static Uint8List _encode(Float32List v) {
    final out = Int8List(v.length);
    for (var k = 0; k < v.length; k++) {
      final q = (v[k] * 127).round();
      out[k] = q < -127 ? -127 : (q > 127 ? 127 : q);
    }
    return out.buffer.asUint8List();
  }

  /// int8 -> float, chuẩn hoá lại để cosine đúng.
  static Float32List _decode(Uint8List bytes) {
    final q = bytes.buffer.asInt8List(bytes.offsetInBytes, bytes.length);
    final out = Float32List(q.length);
    var sum = 0.0;
    for (var k = 0; k < q.length; k++) {
      final x = q[k] / 127.0;
      out[k] = x;
      sum += x * x;
    }
    if (sum > 0) {
      final inv = 1.0 / math.sqrt(sum);
      for (var k = 0; k < out.length; k++) {
        out[k] = out[k] * inv;
      }
    }
    return out;
  }
}
