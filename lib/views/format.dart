import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// "Salman KV" -> "SK", "Salman" -> "S".
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final s = parts.length == 1 ? parts.first[0] : '${parts.first[0]}${parts.last[0]}';
  return s.toUpperCase();
}

/// "09:05 AM" in the company timezone.
String fmtTime(DateTime? utc, String timezone) {
  if (utc == null) return '--:--';
  final local = tz.TZDateTime.from(utc.toUtc(), tz.getLocation(timezone));
  return DateFormat('hh:mm a').format(local);
}

/// "2026-09-30" -> "30/09/2026"
String fmtDmy(String? yyyyMmDd) {
  if (yyyyMmDd == null) return 'DD/MM/YYYY';
  return DateFormat('dd/MM/yyyy').format(DateTime.parse(yyyyMmDd));
}

/// "2026-11-16" -> "Mon, 16 Nov"
String fmtDayLabel(String yyyyMmDd) => DateFormat('EEE, d MMM').format(DateTime.parse(yyyyMmDd));

/// "2026-11-16" -> "Monday, 16 Nov 2026"
String fmtLongDate(String yyyyMmDd) =>
    DateFormat('EEEE, d MMM yyyy').format(DateTime.parse(yyyyMmDd));

/// 04:32:10
String fmtClock(Duration? d) {
  final x = d ?? Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(x.inHours)}:${two(x.inMinutes.remainder(60))}:${two(x.inSeconds.remainder(60))}';
}

/// 9h 10m  (45m under an hour, 30s under a minute)
String fmtDuration(Duration? d) {
  if (d == null) return '--';
  if (d.inHours >= 1) {
    return '${d.inHours}h ${d.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
