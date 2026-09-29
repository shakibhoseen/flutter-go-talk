class PriceHelper {
  static const List<String> _compactSuffixes = ['K', 'M', 'B', 'T', 'P', 'E'];

  static String? shortPriceToKMB(String? value) {
    // Try parsing the string to a double
    final number = double.tryParse(value ?? '');

    // If parsing fails, return the original string (or handle the error as needed)
    if (number == null) {
      return value;
    }

    // If the number is less than 1000, return it as is
    if (number < 1000) {
      return number.toStringAsFixed(
        0,
      ); // No decimals for numbers less than 1000
    }

    // Define suffixes for various number ranges
    final suffixes = <String>[
      'K',
      'M',
      'B',
      'T',
      'P',
      'E',
    ]; // Thousand, Million, Billion, etc.
    final magnitude =
        number.toStringAsFixed(0).length - 1; // Get the number of digits
    var suffixIndex = (magnitude / 3).floor() - 1; // Calculate the suffix index

    // If the number is too large, return with the largest possible suffix
    if (suffixIndex >= suffixes.length) {
      suffixIndex = suffixes.length - 1;
    }

    // Calculate the formatted number with one decimal place
    final formattedNumber = number / (1000.0 * (suffixIndex + 1));

    // Return the formatted number with the appropriate suffix
    return '${formattedNumber.toStringAsFixed(1)}${suffixes[suffixIndex]}';
  }

  static int stringToInt(String str) {
    try {
      // Convert the string to a double and then to an int
      final value = double.parse(str);
      return value.toInt();
    } catch (e) {
      // Handle error if the string cannot be parsed as a number
      return 0; // Return 0 or any default value in case of error
    }
  }

  static String? stringPriSize(String? str, {int maxDecimalPlaces = 2}) {
    //"2346.00" to "2346", "345.80" to "345.8" ; only for show
    if (str == null) return null;
    try {
      // Try parsing the string to a double
      final number = double.parse(str);
      // If the number is an integer (no decimal part), return as integer
      if (number == number.toInt()) {
        return number.toInt().toString();
      }
      // Format to maxDecimalPlaces and remove trailing zeros and decimal point
      final formatted = number
          .toStringAsFixed(maxDecimalPlaces)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
      return formatted;
    } catch (e) {
      return str; // Fallback to original string if parsing fails
    }
    // try {
    //   final list = str.split("."); // Decimal point only
    //   if (list.length == 1) return list.first; // No decimal part
    //   final decimalPart = list[1]; // take Decimal part
    //   if (decimalPart.replaceAll("0", "").isEmpty) return list.first; // Only Decimal part is zeros then return integer part
    //   final trimmedDecimal = decimalPart.replaceAll(RegExp(r'0+$'), ''); //remove Trailing zeros
    //   if (trimmedDecimal.isEmpty) return list.first; // If trimmedDecimal is empty
    //   return "${list.first}.$trimmedDecimal"; // Integer + trimmed decimal
    // } catch (e) {
    //   return str; // Error হলে original string
    // }
  }

  static double? calculateDiscountPercentage(
    String? regularPrice,
    String? discountPrice,
  ) {
    final regular = parsePrice(regularPrice);
    final discount = parsePrice(discountPrice);

    // Check if both prices are valid and non-zero
    if (regular == null || discount == null || regular == 0) {
      return null;
    }

    // Calculate discount percentage
    return ((regular - discount) / regular) * -100;
  }

  /// Converts a string (e.g., "65", "456.5") to a double for calculations
  static double? parsePrice(String? priceString) {
    if (priceString == null) return null;
    try {
      // Try parsing as double
      return double.parse(priceString);
    } catch (e) {
      // Handle invalid format (e.g., "abc", "123..5")
      return null;
    }
  }

  static String compactCount(num value, {int maxDecimalPlaces = 1}) {
    final absValue = value.abs();
    if (absValue < 1000) {
      return value.toStringAsFixed(0);
    }

    var compactValue = value.toDouble();
    var suffixIndex = -1;

    while (compactValue.abs() >= 1000 &&
        suffixIndex < _compactSuffixes.length - 1) {
      compactValue /= 1000;
      suffixIndex++;
    }

    var formatted = _trimTrailingZeros(
      compactValue.toStringAsFixed(maxDecimalPlaces),
    );

    if ((double.tryParse(formatted) ?? compactValue.abs()) >= 1000 &&
        suffixIndex < _compactSuffixes.length - 1) {
      compactValue /= 1000;
      suffixIndex++;
      formatted = _trimTrailingZeros(
        compactValue.toStringAsFixed(maxDecimalPlaces),
      );
    }

    return '$formatted${_compactSuffixes[suffixIndex]}';
  }

  /// "60000" -> "৳60,000", or "৳60,000.00" with [decimals].
  ///
  /// Whole taka by default: every commission figure the affiliate screens show
  /// is rounded. The wallet balance is the exception and asks for two.
  static String taka(num value, {int decimals = 0}) =>
      '৳${grouped(value, decimals: decimals)}';

  /// Thousands separators, western 3-digit grouping.
  ///
  /// BD convention would group a lakh as "1,00,000"; the mock's largest number
  /// is 60,000, which reads the same either way, so this is the open question
  /// to settle before a six-figure commission shows up.
  static String grouped(num value, {int decimals = 0}) {
    final text = value.abs().toStringAsFixed(decimals);
    final dot = text.indexOf('.');
    final whole = dot == -1 ? text : text.substring(0, dot);
    final fraction = dot == -1 ? '' : text.substring(dot);
    // Anchored on the end of the whole part, not the end of the string — with
    // decimals in play `(\d{3})+$` would otherwise group the fraction too.
    final withSeparators = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]},',
    );
    final formatted = '$withSeparators$fraction';
    return value < 0 ? '-$formatted' : formatted;
  }

  /// "120000" -> "৳1,20,000" — Bangladeshi lakh grouping.
  ///
  /// The wallet designs spell the balance this way, which [grouped] cannot
  /// produce: BD groups the last three digits and then every two above them.
  /// Kept beside [taka] rather than inside it because the affiliate screens
  /// already ship western grouping and changing those is a separate call.
  static String takaBd(num value, {int decimals = 0}) =>
      '৳${groupedBd(value, decimals: decimals)}';

  /// Last three digits, then two at a time: 1,20,000 — not 120,000.
  static String groupedBd(num value, {int decimals = 0}) {
    final text = value.abs().toStringAsFixed(decimals);
    final dot = text.indexOf('.');
    final whole = dot == -1 ? text : text.substring(0, dot);
    final fraction = dot == -1 ? '' : text.substring(dot);

    String formatted;
    if (whole.length <= 3) {
      formatted = whole;
    } else {
      final last3 = whole.substring(whole.length - 3);
      final rest = whole.substring(0, whole.length - 3);
      // Anchored on the end of `rest`, so the pairs build leftwards from the
      // last-three boundary and a leading odd digit is left alone.
      final pairs = rest.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+$)'),
        (match) => '${match[1]},',
      );
      formatted = '$pairs,$last3';
    }

    return value < 0 ? '-$formatted$fraction' : '$formatted$fraction';
  }

  /// Zero-pads a count to [minDigits] — the report's "03 pending orders".
  static String padded(num value, {int minDigits = 1}) =>
      value.abs().toStringAsFixed(0).padLeft(minDigits, '0');

  static String _trimTrailingZeros(String value) {
    return value.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
