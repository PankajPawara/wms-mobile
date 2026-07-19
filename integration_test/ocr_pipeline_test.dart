import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:wms_mobile/core/services/memo_ocr_engine.dart';
import 'package:wms_mobile/core/database/app_database.dart';
import 'package:wms_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OCR test pipeline', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();
    
    final db = AppDatabase();
    await db.into(db.inventory).insert(
          InventoryCompanion.insert(
            partNo: '153146-KRB-901',
            barcode: '153146KRB901',
            version: '1',
            description: const Value('GRIP COMP THROT ACTIVA'),
            location: '015R',
            stock: const Value(10),
            price: const Value(118.0),
          ),
        );
    await db.into(db.inventory).insert(
          InventoryCompanion.insert(
            partNo: '114510-KPL-900',
            barcode: '114510KPL900',
            version: '1',
            description: const Value('TENSIONER COMP CAM'),
            location: '063A',
            stock: const Value(5),
            price: const Value(53.0),
          ),
        );
    
    final images = [
      'assets/test_images/test1.jpg',
      'assets/test_images/test2.jpg',
      'assets/test_images/test3.jpg',
      'assets/test_images/test4.jpg',
      'assets/test_images/test5.jpg',
    ];
    
    final tempDir = await getTemporaryDirectory();
    
    for (var i = 0; i < images.length; i++) {
      print('\n\n======================================================');
      print('=== RUNNING TEST ${i + 1} (${images[i]}) ===');
      print('======================================================\n');
      
      try {
        final byteData = await rootBundle.load(images[i]);
        final file = File('${tempDir.path}/test${i+1}.jpg');
        await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
        
        final result = await MemoOcrEngine.process(file, db);
        
        print('\n[RAW DUMP PREVIEW]');
        if (result.rawOcrDump.length > 200) {
           print(result.rawOcrDump.substring(0, 200) + '...');
        } else {
           print(result.rawOcrDump);
        }
        
        print('\n[HEADER VALIDATION]');
        print('Customer: ${result.header.customerName}');
        print('Memo No: ${result.header.memoNumber}');
        print('Area: ${result.header.area}');
        print('Date: ${result.header.memoDate}');
        
        print('\n[ITEM VALIDATION] - Total Extracted: ${result.items.length}');
        for (var j = 0; j < result.items.length; j++) {
          final item = result.items[j];
          print('ROW ${j+1}: ${item.correctedPartNo.padRight(20)} | QTY: ${item.qty.toString().padRight(4)} | LOC: ${item.location.padRight(8)} | MRP: ${item.mrp.toString().padRight(8)} | DESC: ${item.description}');
        }
        
      } catch (e, stack) {
        print('Error processing image ${images[i]}: $e\n$stack');
      }
    }
    
    print('\n======================================================');
    print('=== ALL TESTS COMPLETED ===');
    print('======================================================\n');
  });
}
