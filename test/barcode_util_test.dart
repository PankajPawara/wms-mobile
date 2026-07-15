import 'package:flutter_test/flutter_test.dart';
import 'package:wms_mobile/core/utils/barcode_util.dart';

void main() {
  group('BarcodeUtil Tests', () {
    
    test('isHondaPartNo correctly identifies hyphenated and unhyphenated part numbers', () {
      expect(BarcodeUtil.isHondaPartNo('12200-K1L-D00'), isTrue);
      expect(BarcodeUtil.isHondaPartNo('12200K1LD00'), isTrue);
      expect(BarcodeUtil.isHondaPartNo('INVALIDPART'), isFalse);
    });

    test('cleanExtractedPartNo correctly cleans and substitutes characters', () {
      // With hyphens (should substitute)
      expect(BarcodeUtil.cleanExtractedPartNo('122OO-K1L-D00'), '12200-K1L-D00');
      expect(BarcodeUtil.cleanExtractedPartNo('L2200-K1L-D00'), '12200-K1L-D00');
      expect(BarcodeUtil.cleanExtractedPartNo('|12200-K1L-D00'), '12200-K1L-D00');
      
      // Without hyphens (returns as is stripped of pipes and spaces)
      expect(BarcodeUtil.cleanExtractedPartNo('| 12200K1LD00 '), '12200K1LD00');
    });

    test('extractPartNumbers handles both formats', () {
      final text = "Some text here 12200-K1L-D00 and another one 98765A1B2C3";
      final extracted = BarcodeUtil.extractPartNumbers(text);
      expect(extracted, contains('12200-K1L-D00'));
      expect(extracted, contains('98765A1B2C3'));
    });

    test('findBestMatch correctly fuzzy matches unhyphenated to hyphenated', () {
      final dbParts = ['12200-K1L-D00', '34567-ABC-001'];
      // The user scans an unhyphenated part
      final bestMatch = BarcodeUtil.findBestMatch('12200K1LD00', dbParts);
      expect(bestMatch, '12200-K1L-D00');
      
      // Test OCR mangling (O for 0)
      final mangledMatch = BarcodeUtil.findBestMatch('122OOK1LD00', dbParts);
      expect(mangledMatch, '12200-K1L-D00');
    });

    test('findBestMatchWithLocation handles fuzzy matches with db map', () {
      final dbPartLocations = {
        '12200-K1L-D00': 'A-01',
        '12200-K1L-D01': 'A-02',
      };
      
      final bestMatch = BarcodeUtil.findBestMatchWithLocation('12200K1LD00', 'A-01', dbPartLocations);
      expect(bestMatch, '12200-K1L-D00');
    });
  });
}
