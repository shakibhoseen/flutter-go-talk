import 'package:intl/intl.dart';

class DateCustom {
  get currentTime => DateTime.now().millisecondsSinceEpoch;
  DateTime dateTime(int timestamp) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  CustomDateHourMin formatTimestampWithTime(int time) {
    DateTime timestamp = dateTime(time);
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final oneWeekAgo = DateTime(now.year, now.month, now.day - 7);

    String formattedDate;
    String formattedTime;

    if (timestamp.isAfter(now.subtract(const Duration(days: 1))) &&
        !isAlmostMidnight(now, timestamp)) {
      // Less than one day ago
      formattedDate = 'Today';
    } else if (timestamp.isAfter(yesterday)) {
      // Yesterday
      formattedDate = 'Yesterday';
    } else if (timestamp.isAfter(oneWeekAgo)) {
      // Within one week, return the day of the week
      formattedDate = DateFormat('EEEE').format(timestamp);
    } else {
      // More than one week ago, return the date in the format 'dd-MM-yyyy'
      formattedDate = DateFormat('dd-MM-yyyy').format(timestamp);
    }

    // Format time as hours:minutes AM/PM
    formattedTime = DateFormat.jm().format(timestamp);

    return CustomDateHourMin(
        dateCompare: formattedDate, hourMinute: formattedTime);
  }
}

class CustomDateHourMin {
  final String dateCompare;
  final String hourMinute;
  CustomDateHourMin({required this.dateCompare, required this.hourMinute});
}

bool isAlmostMidnight(DateTime now, DateTime timestamp) {
  // Check if the timestamp is very close to midnight
  return timestamp.day != now.day;
}
