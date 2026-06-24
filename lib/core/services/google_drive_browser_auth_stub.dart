class GoogleDriveBrowserAuth {
  GoogleDriveBrowserAuth._();

  static Future<void> openUrl(String url) async {
    throw UnsupportedError('Opening a browser is not supported here.');
  }

  static Future<Map<String, dynamic>> authorize({
    required String clientId,
    required String clientSecret,
    required String scope,
  }) async {
    throw UnsupportedError(
        'Browser Google authorization is not supported here.');
  }
}
