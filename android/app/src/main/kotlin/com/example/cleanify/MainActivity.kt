package com.example.cleanify

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PhotoEditsChannel(applicationContext).register(flutterEngine)
    }
}

/// Bản Android của kênh "cleanify/photo_edits" (xem AppDelegate.swift cho bản iOS).
/// Mọi số liệu đọc từ MediaStore và StatFs, không tải file, không đụng mạng.
///
/// Khác biệt so với iOS, đã phản ánh trong photo_edits.dart:
///  - `originalThumbs` luôn rỗng: Android không giữ bản gốc bên trong ảnh đã chỉnh.
///  - `editedIds` là suy đoán theo DATE_MODIFIED, không phải cờ chính thức.
class PhotoEditsChannel(private val context: Context) {

    private val resolver: ContentResolver get() = context.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val ids = call.argument<List<String>>("ids") ?: emptyList()
                when (call.method) {
                    "editedIds" -> reply(result, emptyList<String>()) { editedIds(ids) }
                    "storage" -> reply(result, emptyMap<String, Long>()) { storage() }
                    "screenshotIds" -> reply(result, emptyList<String>()) { screenshotIds() }
                    "fileSizes" -> reply(result, emptyMap<String, Long>()) { fileSizes(ids) }
                    "sha256" -> reply(result, emptyMap<String, String>()) { sha256(ids) }
                    "signatures" -> reply(result, emptyMap<String, String>()) { signatures() }
                    // Android không có "bản gốc trước khi chỉnh" như PhotoKit.
                    "originalThumbs" -> result.success(emptyMap<String, ByteArray>())
                    else -> result.notImplemented()
                }
            }
    }

    /// Chạy [work] ngoài luồng giao diện rồi trả kết quả về luồng chính.
    /// Lỗi không ném sang Dart mà trả [fallback]: thiếu số liệu thì giao diện hiện "—",
    /// còn việc quét vẫn chạy bình thường.
    private fun <T> reply(result: MethodChannel.Result, fallback: T, work: () -> T) {
        worker.execute {
            val out = try {
                work()
            } catch (e: Throwable) {
                fallback
            }
            main.post { result.success(out) }
        }
    }

    /// Hai bảng media mà quyền READ_MEDIA_IMAGES / READ_MEDIA_VIDEO cho đọc.
    /// Dùng thẳng hai bảng này thay vì bảng Files gộp, vì từ Android 10 bộ nhớ
    /// phạm vi (scoped storage) không bảo đảm Files trả về đủ.
    /// Từ Android 10, EXTERNAL_CONTENT_URI chỉ phủ ổ ngoài CHÍNH. Ảnh nằm trên
    /// thẻ nhớ thuộc một volume khác nên truy vấn không thấy, và mọi số liệu
    /// metadata trả về rỗng — người dùng thấy ảnh không có dung lượng, còn bộ
    /// lọc trước khi băm thì mất tác dụng hoàn toàn. VOLUME_EXTERNAL phủ hết.
    private fun mediaUris(): List<Uri> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) listOf(
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL),
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL),
        ) else listOf(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        )

    /// photo_manager dùng MediaStore._ID làm AssetEntity.id, nên id từ Dart ghép
    /// thẳng vào mệnh đề IN. _ID là duy nhất trên toàn cơ sở dữ liệu MediaStore
    /// nên quét cả hai bảng không sợ trùng khóa. Chia lô vì SQLite giới hạn số
    /// tham số buộc cho một câu truy vấn.
    private fun queryIds(
        ids: List<String>,
        projection: Array<String>,
        each: (android.database.Cursor) -> Unit,
    ) {
        for (chunk in ids.chunked(BATCH)) {
            if (chunk.isEmpty()) continue
            val holes = chunk.joinToString(",") { "?" }
            val where = "${MediaStore.MediaColumns._ID} IN ($holes)"
            val args = chunk.toTypedArray()
            for (uri in mediaUris()) {
                resolver.query(uri, projection, where, args, null)
                    ?.use { c -> while (c.moveToNext()) each(c) }
            }
        }
    }

    /// Dung lượng file theo id, đọc từ cột SIZE của MediaStore.
    private fun fileSizes(ids: List<String>): Map<String, Long> {
        if (ids.isEmpty()) return emptyMap()
        val out = HashMap<String, Long>(ids.size)
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.SIZE)
        queryIds(ids, projection) { c ->
            val id = c.getLong(c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
            val size = c.getLong(c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE))
            out[id.toString()] = size
        }
        return out
    }

    /// Chữ ký MediaStore của MỌI ảnh trong một truy vấn: "dung lượng|thế hệ".
    ///
    /// Dùng để biết ảnh nào KHÔNG đổi kể từ lần quét trước, khỏi giải mã và băm
    /// lại. Dung lượng đổi khi file bị chỉnh/nén lại. GENERATION_MODIFIED (Android
    /// 11+) là bộ đếm mà chính MediaStore tăng mỗi khi dòng bị sửa, kể cả khi
    /// DATE_MODIFIED không đổi, nên bắt được cả ảnh bị ghi đè rồi chỉnh lại ngày.
    /// Máy cũ không có cột này thì thế hệ = 0 và phía Dart chỉ so dung lượng.
    ///
    /// Một truy vấn cho cả thư viện, không mở file nào.
    private fun signatures(): Map<String, String> {
        val out = HashMap<String, String>()
        val withGen = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        val projection = if (withGen) arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.GENERATION_MODIFIED,
        ) else arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.SIZE,
        )
        val base = mediaUris().first() // bảng ảnh
        resolver.query(base, projection, null, null, null)?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val iSize = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val iGen = if (withGen)
                c.getColumnIndexOrThrow(MediaStore.MediaColumns.GENERATION_MODIFIED)
            else -1
            while (c.moveToNext()) {
                val gen = if (iGen >= 0) c.getLong(iGen) else 0L
                out[c.getLong(iId).toString()] = "${c.getLong(iSize)}|$gen"
            }
        }
        return out
    }

    /// SHA-256 (hex) của file gốc, đọc thẳng qua ContentResolver.
    ///
    /// Đường cũ bên Dart phải nhờ photo_manager chép ảnh ra thư mục cache rồi
    /// đọc lại; ở đây luồng đọc đi thẳng từ MediaStore nên mỗi ảnh chỉ bị đọc
    /// một lần và không có gì được ghi ra đĩa. Kết quả là cùng một con số.
    ///
    /// Id nào không mở được thì bỏ qua: người gọi tự lùi về đường cũ cho nó.
    private fun sha256(ids: List<String>): Map<String, String> {
        if (ids.isEmpty()) return emptyMap()
        val out = HashMap<String, String>(ids.size)
        val buf = ByteArray(1 shl 16)
        val hex = StringBuilder(64)
        for (id in ids) {
            val num = id.toLongOrNull() ?: continue
            for (base in mediaUris()) {
                try {
                    resolver.openInputStream(ContentUris.withAppendedId(base, num))
                        ?.use { input ->
                            val md = MessageDigest.getInstance("SHA-256")
                            while (true) {
                                val r = input.read(buf)
                                if (r <= 0) break
                                md.update(buf, 0, r)
                            }
                            hex.setLength(0)
                            for (b in md.digest()) {
                                val v = b.toInt() and 0xFF
                                if (v < 0x10) hex.append('0')
                                hex.append(Integer.toHexString(v))
                            }
                            out[id] = hex.toString()
                        }
                } catch (e: Throwable) {
                    // Id không thuộc bảng này, hoặc không đọc được: thử bảng sau.
                }
                if (out.containsKey(id)) break
            }
        }
        return out
    }

    /// Tổng và còn trống của bộ nhớ trong (byte), cùng phân vùng mà người dùng
    /// thấy trong Cài đặt > Bộ nhớ.
    private fun storage(): Map<String, Long> {
        val st = StatFs(Environment.getDataDirectory().absolutePath)
        return mapOf("total" to st.totalBytes, "free" to st.availableBytes)
    }

    /// Id mọi ảnh chụp màn hình, mới nhất trước. Android không có cờ riêng như iOS
    /// nên nhận diện theo thư mục "Screenshots" mà hệ thống luôn lưu vào.
    @Suppress("DEPRECATION") // MediaStore.Images.Media.DATA, chi dung duoi API 29.
    private fun screenshotIds(): List<String> {
        val out = ArrayList<String>()
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection: String
        val args: Array<String>
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selection = "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ?" +
                " OR ${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} LIKE ?"
            args = arrayOf("%Screenshots%", "%Screenshot%")
        } else {
            selection = "${MediaStore.Images.Media.DATA} LIKE ?"
            args = arrayOf("%/Screenshots/%")
        }
        resolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            args,
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { c ->
            val i = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (c.moveToNext()) out.add(c.getLong(i).toString())
        }
        return out
    }

    /// Ảnh nhiều khả năng đã bị chỉnh sửa: file được sửa muộn hơn lúc thêm vào máy.
    /// Chỉ là suy đoán (Android không ghi cờ "đã chỉnh"), và chỉ dùng để gắn nhãn
    /// cảnh báo khi xóa, nên đoán thừa an toàn hơn đoán thiếu. [GRACE] giây bỏ qua
    /// chênh lệch do hệ thống ghi metadata ngay sau khi chép ảnh.
    private fun editedIds(ids: List<String>): List<String> {
        if (ids.isEmpty()) return emptyList()
        val out = ArrayList<String>()
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        queryIds(ids, projection) { c ->
            val id = c.getLong(c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
            val added = c.getLong(c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED))
            val changed = c.getLong(c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED))
            if (added > 0 && changed > added + GRACE) out.add(id.toString())
        }
        return out
    }

    private companion object {
        const val CHANNEL = "cleanify/photo_edits"

        /// SQLite chỉ nhận khoảng 999 tham số buộc cho một câu truy vấn.
        const val BATCH = 400

        /// DATE_ADDED và DATE_MODIFIED tính bằng giây.
        const val GRACE = 120L
    }
}
