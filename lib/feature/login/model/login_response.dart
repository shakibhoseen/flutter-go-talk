class LoginResponse {
  String? token;
  String? refreshToken;
  User? user;

  LoginResponse({this.token, this.refreshToken, this.user});

  LoginResponse.fromJson(Map<String, dynamic> json) {
    token = json['access_token'] ?? json['token'];
    refreshToken = json['refresh_token'];
    user = json['user'] != null ? User.fromJson(json['user']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['access_token'] = token;
    data['refresh_token'] = refreshToken;
    if (user != null) {
      data['user'] = user!.toJson();
    }
    return data;
  }

  bool get hasTokens => (token?.isNotEmpty ?? false) && (refreshToken?.isNotEmpty ?? false);
}

class User {
  int? id;
  String? name;
  String? email;
  String? bio;
  String? avatarUrl;
  String? createdAt;

  User({this.id, this.name, this.email, this.bio, this.avatarUrl, this.createdAt});

  User.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    email = json['email'];
    bio = json['bio'];
    avatarUrl = json['avatar_url'] ?? json['image_url'] ?? json['avatar'] ?? json['imageUrl'];
    createdAt = json['created_at'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['name'] = name;
    data['email'] = email;
    data['bio'] = bio;
    data['avatar_url'] = avatarUrl;
    data['created_at'] = createdAt;
    return data;
  }
}
