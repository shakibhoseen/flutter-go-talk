const String url = "https://admin.shop.packly.com/api/v1/ecommerce/";
const String parcelBaseUrl = 'http://192.168.10.240:8088/api/';

final class NetworkConstants {
  NetworkConstants._();

  static const ACCEPT = "Accept";
  static const APP_KEY = "App-Key";
  static const ACCEPT_LANGUAGE = "Accept-Language";

  static const ACCEPT_TYPE = "application/json";
  static const AUTHORIZATION = "Authorization";
  static const CONTENT_TYPE = "content-Type";
}

final class Endpoints {
  Endpoints._();

  /// Parcel Section
  static String parcelMerchantLogin() => "merchant/login";

  static String parcelDestinationLocationStore() =>
      "merchant/parcel-destinations/store";

  static String searchPlaces(String query) =>
      "https://api.openrouteservice.org/geocode/search?api_key=5b3ce3597851110001cf6248085305b562f643b993269f663863ec84&text=$query";

  static String sendExpressParcelReq() => "merchant/parcels/store";

  static String cancelRequest(String parcelId) =>
      "merchant/parcels/request-cancel/$parcelId";

  static String checkCouponValidity(String amount, String couponCode) =>
      "merchant/parcels/coupon-validation?code=$couponCode&amount=$amount";

  static String saveNewAddress() => "merchant/merchant-addresses/store";

  static String getAllSavedAddress() => 'merchant/merchant-addresses';

  static String deleteAddress(int addressId) =>
      'merchant/merchant-addresses/destroy/$addressId';

  static String updateAddress(int addressId) =>
      'merchant/merchant-addresses/update/$addressId';

  static String getAllParcelsHistory() => 'merchant/parcels/history';

  static String giveRiderRating(int parcelId) =>
      'merchant/rider-reviews/update-or-create/$parcelId';

  static String getMasterAPIData() => 'master';

  static String getExpressParcelDetails(String parcelId) =>
      'merchant/parcels/show/$parcelId';

  static String getRegularParcelDetails(String parcelId) =>
      'merchant/regular-parcels/show/$parcelId';

  static String getReqParcelDetails() => 'merchant/regular-parcels/details';

  static String sendRegularParcelDeliveryRequest() =>
      'merchant/regular-parcels/store';

  static String getParcelsLocation() => 'locations';

  static String deviceTokenUpdate() => 'merchant/device-token/update';

  static String ecommerceDeviceTokenStore() => 'device/token-store';

  static String ecommerceDeviceTokenRevoke() => 'device/token-revoke';

  static String getAllIssues() => 'merchant/parcels/reports';

  static String sendReport(String parcelId) =>
      'merchant/parcels/merchant/report/$parcelId';

  static String paymentSuccess(String parcelId) =>
      'merchant/payment/process/$parcelId';

  static String sslPaymentSuccess(String uuid) =>
      'merchant/payment/success/$uuid';

  static String sslPaymentFailed(String uuid) => 'merchant/payment/fail/$uuid';

  static String getMessage(String parcelId) => "/merchant/chats/$parcelId";

  static String sendMessage(String parcelId) => "/merchant/chat/$parcelId";

  /// Main login
  static String login() => "login";

  static String sendOtp() => "send-otp";

  static String forgetPassSentOtp() => "reset-password";

  static String resetPassword() => "reset-confirm";

  static String userUpdate() => "profile/update";

  static String verifyOtp() => "verify-otp";

  static String register() => "register";

  static String setNewPassword() => "new-password";

  static String changePassword() => "change-password";

  static String logOut() => 'logout';

  static String deleteAccount() => "account/delete-request";

  static String deleteAccountStatus() => "account/delete-request/status";

  static String profile() => "profile";

  static String getNewsList() => 'get/news';

  static String getNotifications() => 'get/notifications';

  static String getBalance() => 'balance';

  static String getBalanceDetails() => 'balance-details';

  static String getRecentPickupRequest() => 'get/pickup-requests';

  static String getPaymentsList() => 'get/payments';

  static String getPaymentDetails(String paymentId) =>
      'get/payment/single/$paymentId';

  static String getAllFrauds() => 'get/frauds';

  static String getMyEntriesFraud() => 'get/my-frauds';

  static String searchFraud() => 'post/fraud/search';

  static String getAllTickets() => 'get/tickets';

  static String getParcelDetails(String parcelId) =>
      'get/consignment/single/$parcelId';

  static String getPickupPoints() => 'get/pickup-points';

  static String addFraud() => 'post/fraud/new';

  static String addPickupPoint() => 'post/pickup-point/new';

  static String getAllAddress() => 'get/districts';

  static String createTicket() => 'post/support/ticket/create';

  static String createConsignment() => 'post/consignment/new';

  static String getConsignmentInfo(String phone) =>
      'get/consignment/getbyphone/$phone';

  static String getBankList() => 'get/banks';

  static String sendPaymentRequest() => 'send/payment-request';

  static String sendPickupRequest() => 'post/pickup-request/submit';

  //*****shop***

  //shop

  static String getCategories() => 'categories';

  static String getVariationByProduct({required String slug}) =>
      'product/$slug/variant';

  static String getPopularProduct() => 'popular-products';

  static String getHomePrimeProduct() => 'prime-view';

  static String getProductDetails({required String slug}) =>
      'shop/product/$slug';

  static String getSliderParent() => 'sliders';

  /// Startup policy endpoint. Lives on the platform base url (one level above
  /// the `ecommerce/` shop base url), not on the shop base url.
  static String getAppStatus() => 'app-status';

  static String getPopularShopList() => 'shops/popular';

  static String getMyOrderOrderList() => 'orders';

  static String getShopToPayOrderList() => 'to-pay/orders';

  static String getShopAllOrderGroupList() => 'all/order/list';

  static String getMyReturnList() => 'my/returns';

  static String getReturnDetails(
          {required String returnId, required String trackingId}) =>
      'my/return/$returnId/$trackingId';

  static String getMyOrderDetails({required String trackingId}) =>
      'customer/orders/$trackingId';

  static String getShopToPayOrderDetails({required String orderId}) =>
      'to-pay/order-detail/$orderId';

  static String searchProducts() => 'shop/products';

  static String forYouProducts() => 'products/shop-for-me';

  static String searchSuggestion() => 'products/suggestions';

  static String getReviewListByProduct({required String slug}) =>
      'product/$slug/reviews';

  static String getReasonsList() => 'reasons';

  static String getMyReviewList() => 'my/reviews';

  static String getToReviewList() => 'to/reviews';

  static String getLocation() => 'location';

  static String getShippingAddressList() => 'customer-address/list';

  static String getAvailableCouponList({required String productId}) =>
      'coupons/$productId';

  static String getShopSetting() =>
      'shop/settings'; // get delivery charge and other details
  static String getCancellationDetails({required String productId}) =>
      'order/cancel/$productId'; // cancel details for single product
  static String getShopDetails({required String merchantId}) =>
      'shop/$merchantId/details'; // shop information collect

  static String getShopWiseProduct({required String merchantId}) =>
      'shop/$merchantId/products'; // shop products

  static String getShopReelList() => 'shops/stories';

  static String getStickyMenuList() => 'sticky-menu';

  static String getExploreMenuList() => 'explore-item';

  static String getShopWishList() => 'wishlist';

  static String getShopMyQuestions({required String slug}) =>
      'product/$slug/my-comments';

  static String getShopAllQuestions({required String slug}) =>
      'product/$slug/comments';

  static String getShopOrderCounts() => 'order/counts';

  static String getShopSliderPromotionProduct() => 'slider/promotions';

  static String getTransactionIdFromDatabase({required String orderId}) =>
      'sslcommerz/create/$orderId';

  static String getPaymentMethodList() =>
      'payment-methods';

  //post
  static String postCheckOut() => 'checkout';

  static String postPaymentSuccess() => 'payment/success';

  static String postWriteReview() => 'reviews';

  static String updateReview({required String reviewId}) => 'review/$reviewId';

  static String postOrderReturn({required String trackingId}) =>
      'order/$trackingId/items/return';

  static String postCreateShippingAddress() => 'customer-address/store';

  static String postUpdateShippingAddress({required String id}) =>
      'customer-address/update/$id';

  static String postCancelProductOrder({required String trackingId}) =>
      'order/$trackingId/items/cancel';

  static String postCouponEligibilityForProduct() =>
      'shop-coupon-product-eligibility';

  static String postShopFollowUnfollow({required String shopId}) =>
      'shop/$shopId/follow';

  static String postShopProductInWishListAddRemove(
          {required String productId}) =>
      'wishlist/toggle/$productId';

  static String postShopQuestion({required String slug}) =>
      'product/$slug/comments/store';

  static String getPostDeleteCart() => 'cart';

  static String getTermsAndConditions() => 'e-pages/terms-and-conditions';

  static String refundAndReturnPolicy() => 'e-pages/refund-and-return-policy';

  static String getFaqs() => 'faqs';
  static String getGiveawayTickets() => 'giveaway/tickets';

  static String getCampaigns() => 'campaigns';

  // reels section
  static String getReelList() => 'reels';
  static String postReelLikeAddRemove({required String reelId}) => 'reels/$reelId/like';
  static String getCommentList({required String reelId}) => 'reels/$reelId/comments';
  static String postCommentOrReply({required String reelId}) => 'reels/$reelId/comments';
  static String postReelViews({required String reelId}) => 'reels/$reelId/views';
  static String postReelShare({required String reelId}) => 'reels/$reelId/share';


  // Two-Factor Authentication (2FA) Endpoints
  static String twoFactorGenerate() => '2fa/generate';
  static String twoFactorEnable() => '2fa/enable';
  static String twoFactorDisable() => '2fa/disable';
  static String twoFactorRecoveryCodes() => '2fa/recovery-codes';
  static String twoFactorRegenerateRecoveryCodes() => '2fa/regenerate-recovery-codes';
  static String twoFactorVerify() => '2fa/verify';

}
