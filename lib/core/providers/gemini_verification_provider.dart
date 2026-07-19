import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:drift/drift.dart' as drift;

import '../database/app_database.dart';
import '../models/extracted_memo.dart';

/// The state of the background Gemini verification process.
enum GeminiVerificationStatus {
  idle,
  running,
  completed,
  failed,
}

class GeminiVerificationState {
  final GeminiVerificationStatus status;
  final List<ExtractedMemoItem> updatedItems;
  final String? errorMessage;
  final String? rawJsonOutput;
  final int processedCount;
  final int totalCount;

  const GeminiVerificationState({
    this.status = GeminiVerificationStatus.idle,
    this.updatedItems = const [],
    this.errorMessage,
    this.rawJsonOutput,
    this.processedCount = 0,
    this.totalCount = 0,
  });

  bool get isRunning => status == GeminiVerificationStatus.running;
  bool get isCompleted => status == GeminiVerificationStatus.completed;
  bool get hasFailed => status == GeminiVerificationStatus.failed;

  GeminiVerificationState copyWith({
    GeminiVerificationStatus? status,
    List<ExtractedMemoItem>? updatedItems,
    String? errorMessage,
    String? rawJsonOutput,
    int? processedCount,
    int? totalCount,
  }) {
    return GeminiVerificationState(
      status:         status         ?? this.status,
      updatedItems:   updatedItems   ?? this.updatedItems,
      errorMessage:   errorMessage,
      rawJsonOutput:  rawJsonOutput  ?? this.rawJsonOutput,
      processedCount: processedCount ?? this.processedCount,
      totalCount:     totalCount     ?? this.totalCount,
    );
  }
}

/// Persistent Riverpod notifier that runs Gemini verification in the background.
/// Lives at the app root — survives screen navigation.
///
/// RULES (enforced in prompt):
///   - Gemini validates/corrects existing rows ONLY.
///   - Gemini CANNOT create new rows.
///   - DB re-validates every Gemini suggestion before accepting it.
class GeminiVerificationNotifier extends StateNotifier<GeminiVerificationState> {
  final AppDatabase _db;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;
  static const _storage = FlutterSecureStorage();
  
  int? _attachedOrderId;

  GeminiVerificationNotifier(this._db) : super(const GeminiVerificationState());

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _notificationsPlugin.initialize(initSettings);
    _notificationsInitialized = true;
  }

  Future<void> _showNotification(String title, String body) async {
    await _initNotifications();
    const android = AndroidNotificationDetails(
      'wms_gemini_channel',
      'AI Verification',
      channelDescription: 'Notifications for Gemini AI processing',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
  }

  void reset() {
    _attachedOrderId = null;
    state = const GeminiVerificationState();
  }

  /// Attach an order ID to this verification run so that if it completes later,
  /// it can automatically update the saved order items in the database.
  void attachOrderId(int orderId) {
    _attachedOrderId = orderId;
    if (state.isCompleted) {
      _updateDatabaseItems(orderId, state.updatedItems);
    }
  }

  Future<void> _updateDatabaseItems(int orderId, List<ExtractedMemoItem> items) async {
    // Delete old items
    await (_db.delete(_db.orderItems)..where((t) => t.orderId.equals(orderId))).go();
    
    // Insert updated items
    for (final item in items) {
      await _db.into(_db.orderItems).insert(OrderItemsCompanion.insert(
        orderId: orderId,
        partNo: item.correctedPartNo,
        description: drift.Value(item.description.isNotEmpty ? item.description : null),
        location: item.location.isNotEmpty ? item.location : 'TEMP-LOC',
        requiredQty: item.qty,
        pickedQty: const drift.Value(0),
        unitPrice: drift.Value(item.mrp),
        finalPrice: drift.Value(item.qty * item.mrp),
        status: const drift.Value('pending'),
        isSynced: const drift.Value(0),
      ));
    }
  }

  /// Initiates the background Gemini verification for low-confidence items.
  /// Provides progress updates via state changes.
  /// Safe to call and then navigate away — updates persist.
  Future<void> verify({
    required List<ExtractedMemoItem> allItems,
    required ExtractedMemoHeader header,
    required String rawOcrDump,
    File? imageFile,
  }) async {
    final lowConfidenceItems = allItems
        .where((i) => i.confidence.needsGemini)
        .toList();

    if (lowConfidenceItems.isEmpty) {
      state = GeminiVerificationState(
        status: GeminiVerificationStatus.completed,
        updatedItems: allItems,
        rawJsonOutput: 'No AI verification needed. All items passed local db validation.',
        processedCount: allItems.length,
        totalCount: allItems.length,
      );
      return;
    }

    state = GeminiVerificationState(
      status: GeminiVerificationStatus.running,
      updatedItems: allItems,
      totalCount: lowConfidenceItems.length,
      processedCount: 0,
    );

    try {
      // Resolve API key
      String? apiKey = await _storage.read(key: 'gemini_api_key');
      if (apiKey == null || apiKey.isEmpty) {
        apiKey = dotenv.env['GEMINI_API_KEY'];
      }
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('GEMINI_API_KEY not configured.');
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      // Build prompt — VALIDATOR ONLY
      final itemsJson = jsonEncode(lowConfidenceItems
          .map((i) => {
                'raw_ocr': i.rawOcrPartNo,
                'corrected': i.correctedPartNo,
                'qty': i.qty,
                'mrp': i.mrp,
                'location': i.location,
                'pack': i.pack,
                'stock': i.stock,
              })
          .toList());

      final prompt = '''
You are a VALIDATOR for Honda auto-parts pickup memos. Your ONLY job is to correct OCR mistakes in the provided items.

RULES (MUST follow):
1. You CANNOT create new items. Only work with the items provided.
2. You CANNOT change location, stock, or description — those come from the database.
3. You CAN correct the part number if you see an obvious OCR mistake.
4. You CAN correct qty, mrp, pack if the values look wrong based on the image.
5. Return ONLY the corrected items in the EXACT same order.
6. Output raw JSON only — no markdown.

Memo Header:
  Customer: ${header.customerName}
  Area: ${header.area}
  Memo No: ${header.memoNumber}
  Date: ${header.memoDate ?? 'unknown'}

RAW OCR DUMP:
$rawOcrDump

ITEMS TO VALIDATE (${lowConfidenceItems.length} items with confidence < 85%):
$itemsJson

OUTPUT FORMAT:
[
  {
    "raw_ocr": "original raw OCR value",
    "corrected_part_no": "corrected part number",
    "qty": 1,
    "mrp": 0.0,
    "pack": 0,
    "stock": 0
  }
]
''';

      final List<Part> parts = [TextPart(prompt)];
      if (imageFile != null && await imageFile.exists()) {
        final bytes = await imageFile.readAsBytes();
        parts.add(DataPart('image/jpeg', bytes));
      }

      final response = await model.generateContent([Content.multi(parts)]);
      final text = response.text ?? '[]';

      // Clean potential markdown wrapping
      String cleanJson = text.trim();
      if (cleanJson.startsWith('```json')) cleanJson = cleanJson.substring(7);
      if (cleanJson.startsWith('```')) cleanJson = cleanJson.substring(3);
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final geminiSuggestions = jsonDecode(cleanJson) as List<dynamic>;

      // Build a map from rawOcr → suggestion for fast lookup
      final suggestionMap = <String, Map<String, dynamic>>{};
      for (final s in geminiSuggestions) {
        final m = s as Map<String, dynamic>;
        final rawOcr = m['raw_ocr']?.toString() ?? '';
        if (rawOcr.isNotEmpty) suggestionMap[rawOcr] = m;
      }

      // Apply corrections — DB re-validates every Gemini suggestion
      final updatedItems = <ExtractedMemoItem>[];
      int processed = 0;

      for (final item in allItems) {
        if (!item.confidence.needsGemini) {
          updatedItems.add(item);
          continue;
        }

        final suggestion = suggestionMap[item.rawOcrPartNo];
        if (suggestion == null) {
          updatedItems.add(item);
          processed++;
          continue;
        }

        final suggestedPartNo = suggestion['corrected_part_no']?.toString().trim().toUpperCase() ?? '';
        if (suggestedPartNo.isEmpty || suggestedPartNo == item.rawOcrPartNo) {
          updatedItems.add(item);
          processed++;
          continue;
        }

        // DB re-validation
        final dbMatch = await (_db.select(_db.inventory)
              ..where((t) => t.partNo.equals(suggestedPartNo)))
            .getSingleOrNull();

        if (dbMatch != null) {
          // Gemini suggestion is DB-confirmed
          final correctedItem = item.copyWith(
            correctedPartNo: suggestedPartNo,
            confidence: MatchConfidence.gemini,
            description: dbMatch.description?.isNotEmpty == true
                ? dbMatch.description!
                : item.description,
            location: dbMatch.location.isNotEmpty ? dbMatch.location : item.location,
            mrp: dbMatch.price > 0 ? dbMatch.price : item.mrp,
            stock: dbMatch.stock > 0 ? dbMatch.stock : item.stock,
            qty: int.tryParse(suggestion['qty']?.toString() ?? '') ?? item.qty,
            pack: int.tryParse(suggestion['pack']?.toString() ?? '') ?? item.pack,
          );
          updatedItems.add(correctedItem);
        } else {
          // Gemini suggestion not in DB — reject it, keep original
          updatedItems.add(item);
        }

        processed++;
        state = state.copyWith(
          processedCount: processed,
          updatedItems: List.unmodifiable(updatedItems + allItems.sublist(updatedItems.length)),
        );
      }

      state = GeminiVerificationState(
        status: GeminiVerificationStatus.completed,
        updatedItems: updatedItems,
        rawJsonOutput: cleanJson,
        processedCount: updatedItems.length,
        totalCount: allItems.length,
      );
      
      if (_attachedOrderId != null) {
        await _updateDatabaseItems(_attachedOrderId!, updatedItems);
      }
      
      _showNotification(
        'AI Verification Complete',
        'Gemini successfully verified and corrected $processed items from the memo.',
      );
    } catch (e) {
      if (kDebugMode) print('[GeminiVerification] Error: $e');
      state = state.copyWith(
        status: GeminiVerificationStatus.failed,
        errorMessage: e.toString(),
      );
      _showNotification(
        'AI Verification Failed',
        'Could not complete Gemini OCR correction.',
      );
    }
  }
}

final geminiVerificationProvider = StateNotifierProvider<
    GeminiVerificationNotifier, GeminiVerificationState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return GeminiVerificationNotifier(db);
});
