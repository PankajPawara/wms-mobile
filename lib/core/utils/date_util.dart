import 'package:intl/intl.dart';

class DateUtil {
  DateUtil._();

  static String format(DateTime? date, {String pattern = 'dd MMM yyyy'}) {
    if (date == null) return '--';
    return DateFormat(pattern).format(date.toLocal());
  }

  static String formatDateTime(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal());
  }

  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return format(date);
  }

  static String formatIso(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--';
    try {
      return format(DateTime.parse(isoString));
    } catch (_) {
      return '--';
    }
  }
}
