class AppConfigModel {
  final String latestApkVersion;
  final String apkDownloadUrl;
  final bool forceApkUpdate;
  final String latestInventoryVersion;

  const AppConfigModel({
    required this.latestApkVersion,
    required this.apkDownloadUrl,
    required this.forceApkUpdate,
    required this.latestInventoryVersion,
  });

  factory AppConfigModel.fromJson(Map<String, dynamic> json) {
    return AppConfigModel(
      latestApkVersion: json['latest_apk_version'] ?? '1.0.0',
      apkDownloadUrl: json['apk_download_url'] ?? '',
      forceApkUpdate: json['force_apk_update'] ?? false,
      latestInventoryVersion: json['latest_inventory_version'] ?? 'v0',
    );
  }
}
