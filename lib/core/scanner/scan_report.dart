import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'scan_diagnostics.dart';
import 'scan_session.dart';

/// Builds a CSV report from the completed in-memory scan. It includes group
/// membership and any PDQ/model evidence already collected; it never exports
/// image bytes.
String scanReportCsv(ScanSession session, {DateTime? exportedAt}) {
  final generated = exportedAt ?? DateTime.now();
  final diag = session.diag;
  final out = StringBuffer()
    ..writeln(
      'exported_at,scan_elapsed_ms,library_total,scanned,incomplete_stages,'
      'group_kind,group_number,group_size,member_number,asset_id,captured_at,'
      'width,height,is_anchor,exact,similarity,by_model,model_cosine,'
      'pdq_hamming,via_original,diag_anchor_id,diag_hamming,diag_pdq_percent,'
      'diag_cos_dino,threshold,reason,verdict',
    );

  final groups = session.groups;
  final incomplete = session.incompleteStages.join('|');
  void writeRow({
    String groupKind = '',
    String groupNumber = '',
    int? groupSize,
    int? memberNumber,
    DuplicateItem? item,
    DiagRow? row,
    String verdict = '',
  }) {
    final asset = item?.asset;
    out.writeln(
      [
        generated.toIso8601String(),
        session.elapsed.inMilliseconds,
        session.libraryTotal,
        session.scanned,
        incomplete,
        groupKind,
        groupNumber,
        groupSize,
        memberNumber,
        asset?.id,
        asset?.createDateTime.toIso8601String(),
        asset?.width,
        asset?.height,
        item == null ? '' : memberNumber == 1,
        item?.exact,
        item?.similarity?.toStringAsFixed(2),
        item?.byModel,
        item?.modelCosine?.toStringAsFixed(4) ??
            row?.cosDino?.toStringAsFixed(4),
        item?.pdqHamming ?? row?.hamming,
        item?.viaOriginal,
        row?.anchorId,
        row?.hamming,
        row?.pdqPercent?.toStringAsFixed(2),
        row?.cosDino?.toStringAsFixed(4),
        row?.threshold,
        row?.reason,
        verdict,
      ].map(csvEscape).join(','),
    );
  }

  if (groups.isEmpty) {
    writeRow();
  } else {
    for (var gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final rows = {
        for (final row in diag?.rowsOf(group) ?? const <DiagRow>[])
          row.assetId: row,
      };
      final verdict = diag?.verdictOf(group)?.symbol ?? '';
      for (var mi = 0; mi < group.items.length; mi++) {
        final item = group.items[mi];
        writeRow(
          groupKind: group.kind.name,
          groupNumber: '${gi + 1}',
          groupSize: group.items.length,
          memberNumber: mi + 1,
          item: item,
          row: rows[item.asset.id],
          verdict: verdict,
        );
      }
    }
  }
  return out.toString();
}

Future<File> writeScanReport(ScanSession session) async {
  final dir = await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final now = DateTime.now();
  final existing = session.reportPath;
  late final File file;
  if (existing != null) {
    file = File(existing);
  } else {
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'cleanify_scan_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.csv';
    file = File('${dir.path}/$name');
  }
  await file.writeAsString(
    scanReportCsv(session, exportedAt: now),
    flush: true,
  );
  if (await file.length() == 0) {
    throw FileSystemException('CSV rỗng sau khi ghi', file.path);
  }
  session.reportPath = file.path;
  session.reportError = null;
  return file;
}
