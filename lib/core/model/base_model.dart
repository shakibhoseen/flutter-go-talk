/// Abstract base class for all data models in the application.
/// 
/// Providing a common contract like [toJson] enables generic type bounds
/// (`T extends BaseModel`) across repositories, local caching, pagination,
/// and database mappers.
abstract class BaseModel {
  const BaseModel();

  /// Converts the model instance into a JSON-compatible map.
  Map<String, dynamic> toJson();
}
