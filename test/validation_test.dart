import 'package:flutter_test/flutter_test.dart';
import 'package:wms_mobile/core/data/validation_data.dart';

void main() {
  int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    List<int> v0 = List<int>.filled(b.length + 1, 0);
    List<int> v1 = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i <= b.length; i++) v0[i] = i;
    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = v1[j] + 1 < v0[j + 1] + 1 ? v1[j] + 1 : v0[j + 1] + 1;
        v1[j + 1] = v1[j + 1] < v0[j] + cost ? v1[j + 1] : v0[j] + cost;
      }
      for (int j = 0; j <= b.length; j++) v0[j] = v1[j];
    }
    return v0[b.length];
  }

  test('Validates model code correctly', () {
    String rPartNo = "180101-KOV-A00";
    String correctedPartNo = rPartNo.toUpperCase();
    
    for (var code in ValidationData.validModelCodes) {
       final mistakeO = code.replaceAll('0', 'O');
       final mistakeI = code.replaceAll('1', 'I');
       final mistakeBoth = mistakeO.replaceAll('1', 'I');

       if (mistakeBoth != code && correctedPartNo.contains(mistakeBoth)) {
          correctedPartNo = correctedPartNo.replaceAll(mistakeBoth, code);
       } else {
         if (mistakeO != code && correctedPartNo.contains(mistakeO)) {
            correctedPartNo = correctedPartNo.replaceAll(mistakeO, code);
         }
         if (mistakeI != code && correctedPartNo.contains(mistakeI)) {
            correctedPartNo = correctedPartNo.replaceAll(mistakeI, code);
         }
       }
    }
    
    expect(correctedPartNo, "180101-K0V-A00");
  });

  test('Validates subArea correctly', () {
    String customerName = "RAHUL PALSMA";
    String area = "NAVSARI";
    String? subArea;

    final normArea = area.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    String? matchedMainArea;
    for (var mainArea in ValidationData.areaSchedules.keys) {
      final normMainArea = mainArea.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
      if (normArea.contains(normMainArea) || _levenshtein(normArea, normMainArea) <= 2) {
        matchedMainArea = mainArea;
        break;
      }
    }

    if (matchedMainArea != null) {
      final subAreas = ValidationData.areaSchedules[matchedMainArea]!;
      for (var sub in subAreas) {
        final subWords = sub.toUpperCase().split(RegExp(r'[^A-Z]')).where((w) => w.isNotEmpty).toList();
        final custWords = customerName.toUpperCase().split(RegExp(r'[^A-Z]')).where((w) => w.isNotEmpty).toList();
        
        for (int i = 0; i <= custWords.length - subWords.length; i++) {
          bool match = true;
          for (int j = 0; j < subWords.length; j++) {
             final maxDist = subWords[j].length >= 5 ? 2 : (subWords[j].length >= 3 ? 1 : 0);
             if (_levenshtein(custWords[i+j], subWords[j]) > maxDist) {
               match = false;
               break;
             }
          }
          if (match) {
            subArea = sub;
            for (int j = 0; j < subWords.length; j++) {
               custWords[i+j] = subWords[j];
            }
            customerName = custWords.join(' ');
            break;
          }
        }
        if (subArea != null) break;
      }
    }

    expect(subArea, "PALSANA");
    expect(customerName, "RAHUL PALSANA");
  });
}
