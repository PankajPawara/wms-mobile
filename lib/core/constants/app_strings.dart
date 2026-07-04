class AppStrings {
  AppStrings._();

  static const String appName = 'WMS';
  static const String appFullName = 'Warehouse Management System';

  // Auth
  static const String login = 'Log In';
  static const String logout = 'Log Out';
  static const String employeeId = 'Employee ID';
  static const String password = 'Password';
  static const String changePassword = 'Change Password';
  static const String currentPassword = 'Current Password';
  static const String newPassword = 'New Password';
  static const String confirmPassword = 'Confirm Password';
  static const String firstLoginMessage =
      'Welcome! Please set your new password before continuing.';

  // Home
  static const String importFile = 'Import Inventory File';
  static const String pickupList = 'Pickup List';
  static const String pickupVerification = 'Checking';
  static const String scanProduct = 'Scan Product';

  // Scan to Find
  static const String scanToFind = 'Scan to Find';
  static const String pointCameraAtBarcode = 'Point camera at a barcode';
  static const String productFound = 'Product Found';
  static const String barcodeNotFound = 'Barcode not found in inventory';

  // OCR
  static const String captureMemo = 'Capture Memo';
  static const String reviewItems = 'Review Extracted Items';
  static const String extracting = 'Extracting...';
  static const String noItemsExtracted = 'No items could be extracted';
  static const String generatePickupList = 'Generate Pickup List';

  // Picking
  static const String startPicking = 'Start Picking';
  static const String scanToConfirm = 'Scan barcode to confirm';
  static const String correctProduct = 'Correct Product';
  static const String wrongProduct = 'Wrong Product!';
  static const String allItemsPicked = 'All items picked!';
  static const String completePicking = 'Complete Picking';

  // Checking
  static const String startChecking = 'Start Checking';
  static const String completeChecking = 'Complete Checking';

  // Common
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String retry = 'Retry';
  static const String loading = 'Loading...';
  static const String noData = 'No data found';
  static const String error = 'Something went wrong';
  static const String offline = 'Working Offline';
  static const String syncing = 'Syncing...';
  static const String syncComplete = 'Sync Complete';
  static const String location = 'Location';
  static const String quantity = 'Quantity';
  static const String partNo = 'Part No';
  static const String description = 'Description';
  static const String required = 'Required';
  static const String picked = 'Picked';
  static const String checked = 'Checked';
}
