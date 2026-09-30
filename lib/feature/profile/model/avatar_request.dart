import 'package:whatsapp_flutter_go/core/model/base_model.dart';

class AvatarResponse extends BaseModel {
  String? avatarUrl;

  AvatarResponse({this.avatarUrl});

  factory AvatarResponse.fromJson(Map<String, dynamic> json) =>
      AvatarResponse(avatarUrl: json["avatar_url"]);

  @override
  Map<String, dynamic> toJson() => {"avatar_url": avatarUrl};
}
