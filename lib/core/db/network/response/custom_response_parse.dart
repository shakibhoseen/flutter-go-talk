class CustomValidationResponseParse {
  bool? success;
  List<String> validations=[];
  String validationText= '';
  String? message;
  Map<String, List<String>> fieldErrors = {};

  CustomValidationResponseParse({this.success});

  CustomValidationResponseParse.fromJson(Map<String, dynamic> json) {
    success = json['success'];
    message = json['message'];
    
    if (json['errors'] != null) {
      final errors = json['errors'];
      
      if (errors is Map) {
        // Handle Map structure: {"field": ["error"]} or {"field": "error"}
        _parseMapErrors(errors);
      } else if (errors is List) {
        // Handle List structure: ["error1", "error2"]
        _parseListErrors(errors);
      } else if (errors is String) {
        // Handle String: "error message"
        validations = [errors];
        validationText = errors;
      }
    }
  }

  void _parseMapErrors(Map errors) {
    errors.forEach((key, value) {
      final fieldName = key.toString();
      if (value is List) {
        final errorList = value.map((e) => e.toString()).toList();
        fieldErrors[fieldName] = errorList;
        validations.addAll(errorList);
      } else {
        final errorStr = value.toString();
        fieldErrors[fieldName] = [errorStr];
        validations.add(errorStr);
      }
    });
    validationText = validations.join('\n');
  }

  void _parseListErrors(List errors) {
    validations = errors.map((e) => e.toString()).toList();
    validationText = validations.join('\n');
    // Note: List errors don't have field mapping
  }

  String? getFieldError(String fieldName) {
    final errors = fieldErrors[fieldName];
    return errors != null && errors.isNotEmpty ? errors.first : null;
  }
}