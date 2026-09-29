class ParseHelper {
  ParseHelper._();

  static int? parseSafetyStringInt(dynamic json) =>
      json is int? ? json : int.parse(json);

  static String? parseSafetyIntToString(dynamic json) =>
      json is String? ? json : '$json';

  //double from any int, double or string
  static double? parseSafetyDouble(dynamic json) => json is double?
      ? json
      : json is int
          ? json.toDouble()
          : double.parse(json);
}
// extension CustomJson on Object{
//    Object get safetyInt => this is int? ? this : int.parse(this as String) ;
// }
