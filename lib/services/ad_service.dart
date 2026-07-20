/// AdService — DISABLED.
/// google_mobile_ads has been removed from pubspec.yaml.
/// Re-add the dependency and restore this file when real AdMob IDs are ready.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  Future<void> init() async {}

  void maybeShowInterstitial() {}

  void showRewardedThen(void Function() onUnlocked) => onUnlocked();

  bool get rewardedReady => false;
}
