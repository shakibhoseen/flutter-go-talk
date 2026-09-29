// ignore_for_file: constant_identifier_names

final class ResponseMessage {
  ResponseMessage._();
  // API response messages
  static const String SUCCESS = "Success"; // Success with data
  static const String NO_CONTENT =
      "Success with no content"; // Success with no data (no content)
  static const String VALIDATION_ERROR =
      "Please check the highlighted information";
  static const String BAD_REQUEST =
      "Bad request. Try again later"; // Failure, API rejected request
  static const String UNAUTHORISED =
      "User unauthorized. Try again later"; // Failure, user is not authorized
  static const String SESSION_EXPIRED =
      "Your session has expired. Please log in again";
  static const String INVALID_CREDENTIALS =
      "Invalid credentials. Please try again";
  static const String INVALID_OTP = "Invalid or expired OTP";
  static const String FORBIDDEN =
      "Forbidden request. Try again later"; // Failure, API rejected request
  static const String INTERNAL_SERVER_ERROR =
      "Something went wrong. Try again later"; // Failure, crash on the server side
  static const String NOT_FOUND =
      "URL not found. Try again later"; // Failure, resource not found
  static const String FILE_TOO_LARGE =
      "File too large. Try again later"; // Failure, resource not found
  static const String TOO_MANY_REQUESTS =
      "Too many attempts. Please try again later";
  static const String MAINTENANCE =
      "The service is temporarily under maintenance";
  static const String FORCE_UPDATE = "Please update the app to continue";
  static const String BUSINESS_ERROR = "Request could not be completed";

  // Local status codes
  static const String CONNECT_TIMEOUT = "Timeout. Try again later";
  static const String CANCEL = "Request canceled";
  static const String RECIEVED_TIMEOUT = "Timeout. Try again later";
  static const String SEND_TIMEOUT = "Timeout. Try again later";
  static const String CACHE_ERROR = "Cache error. Try again later";
  static const String NO_INTERNET_CONNECTION =
      "Please check your internet connection";
  static const String DEFAULT = "Something went wrong";

  // Add more descriptive comments or documentation as needed
}

final class ResponseCode {
  ResponseCode._();
  static const int SUCCESS = 200; // success with data
  static const int NO_CONTENT = 204; // success with no data (no content)
  static const int BAD_REQUEST = 400; // failure, API rejected request
  static const int UNAUTHORISED = 401; // failure, user is not authorised
  static const int FORBIDDEN = 403; //  failure, API rejected request
  static const int NOT_FOUND = 404; // failure, not found
  static const int CONFLICT = 409; // failure, request conflicts with state
  static const int UNPROCESSABLE_ENTITY = 422; // failure, validation failed
  static const int TOO_MANY_REQUESTS = 429; // failure, rate limit hit
  static const int INTERNAL_SERVER_ERROR = 500; // failure, crash in server side
  static const int SERVICE_UNAVAILABLE = 503; // failure, maintenance mode
  static const int FORCE_UPDATE_REQUIRED = 505; // failure, app update required
  static const int FILE_TOO_LARGE = 413; // failure, not found

  // local status code
  static const int CONNECT_TIMEOUT = -1;
  static const int CANCEL = -2;
  static const int RECEIVED_TIMEOUT = -3;
  static const int SEND_TIMEOUT = -4;
  static const int CACHE_ERROR = -5;
  static const int NO_INTERNET_CONNECTION = -6;
  static const int DEFAULT = -7;
  static const int BUSINESS_ERROR = -8;
}
