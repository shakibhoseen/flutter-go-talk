/// Renders a timestamp the way a comment thread shows it — `now`, `4m`, `3h`,
/// `2d`, then a date once it stops being useful to count.
///
/// Short forms rather than "4 minutes ago": these sit inline next to a name in
/// a row that also has to fit an avatar and the comment itself.
String relativeTime(DateTime dateTime, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(dateTime);

  if (elapsed.isNegative || elapsed.inSeconds < 60) return 'now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  if (elapsed.inDays < 365) return '${elapsed.inDays ~/ 7}w';
  return '${elapsed.inDays ~/ 365}y';
}
