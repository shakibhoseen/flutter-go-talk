final class AppRegExpText {
  AppRegExpText._();

// Regular Expression
  static String kRegExpEmail =
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+";
  static String kRegExpPhone =
      // ignore: prefer_adjacent_string_concatenation
      "(\\+[0-9]+[\\- \\.]*)?(\\([0-9]+\\)[\\- \\.]*)?" +
          "([0-9][0-9\\- \\.]+[0-9])";

  static String patternMail =
      r"^(([^<>()[\]\\.,;:\s@\']+(\.[^<>()[\]\\.,;:\s@\']+)*)|(\'.+\'))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$";
}

const String kImageUrl = 'imageUrl';
// Keys
const String kKeyStatus = 'status';
const String kKeyJsonObject = 'json_object';
const String kKeyJsonArray = 'json_array';
const String kKeyStringData = 'string_data';
const String kKeyMessage = 'message';
const String kKeyData = 'data';
const String kKeyCode = 'code';
const String kKeyIsLoggedIn = 'is_logged_in';
const String kKeyHasPassword = 'has_set_password';
const String kKeyAccessToken = 'access_token';
const String kKeyUserRole = 'user_role';
const String kKeyIsNotFirstTime = 'first_time_user';
const String kKeySaveUserAuthList = 'save_user_password_list';
const String kKeyUserProfile = 'save_user_profile';
const String kKeyGuestCartSyncPending = 'guest_cart_sync_pending';
const String kKeyDevMood = 'dev_mood';
const String kKeyChatBaseUrlOverride = 'chat_base_url_override';
const String kKeyParcelBaseUrlOverride = 'parcel_base_url_override';
const String kKeyReelBaseUrlOverride = 'reel_base_url_override';
const String kKeyPlatformBaseUrlOverride = 'platform_base_url_override';
const String kKeyAuthBaseUrlOverride = 'auth_base_url_override';

const String defaultImageUrl =
    'https://easy-peasy.ai/cdn-cgi/image/quality=80,format=auto,width=700/https://fdczvxmwwjwpwbeeqcth.supabase.co/storage/v1/object/public/images/642a47ed-9f59-4c02-b9a3-2ff875179476/066b0ee9-c0d4-40f8-b9ef-5ea270079e35.png';
const String natureImage =  'https://png.pngtree.com/background/20230412/original/pngtree-nature-forest-sun-ecology-picture-image_2394782.jpg';

class DefaultValue {
  static const bool kDefaultBoolean = false;
  static const int kDefaultInt = 0;
  static const double kDefaultDouble = 0.0;
  static const String kDefaultString = '';
}

class AuthRoleValue {
  static const int kSuperAdmin = 1;
  static const int kAdmin = 2;
  static const int kUnionManager = 3;
  static const int kWordManager = 4;
  static const int kVolunteer = 5;
  static const int kVoter = 6;
}

class ShopConstantValue{
  static const int showAllAskQuestionLimitInProductDetails = 1;
  static const int showMyAskQuestionLimitInProductDetails = 1;
}
