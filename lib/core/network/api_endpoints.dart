class ApiEndpoints {
  ApiEndpoints._();

  // Use 192.168.40.225 to access your PC's backend from a physical phone on the same Wi-Fi
  static const String baseUrl = 'http://192.168.40.225:5000/api';

  // Auth
  static const String login = '/auth/login';
  static const String changePassword = '/auth/change-password';
  static const String me = '/auth/me';

  // Inventory
  static const String inventoryVersion = '/inventory/version';
  static const String inventoryDownload = '/inventory/download';
  static String inventoryBarcode(String barcode) => '/inventory/barcode/$barcode';
  static const String inventorySearch = '/inventory/search';

  // Orders
  static const String orders = '/orders';
  static String orderById(String id) => '/orders/$id';
  static String orderStatus(String id) => '/orders/$id/status';
  static String orderItem(String orderId, String itemId) =>
      '/orders/$orderId/items/$itemId';

  // Sync
  static const String syncStatus = '/sync/status';
  static const String syncOrders = '/sync/orders';
  static const String syncOrderItems = '/sync/order-items';

  // System
  static const String systemHealth = '/system/health';
  static const String systemInfo = '/system/info';
}
