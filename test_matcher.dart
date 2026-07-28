import 'dart:math';

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
      v1[j + 1] = min(v0[j] + cost, min(v1[j] + 1, v0[j + 1] + 1));
    }
    for (int j = 0; j <= b.length; j++) v0[j] = v1[j];
  }
  return v0[b.length];
}

class MatchResult {
  final int cost;
  final int startRaw;
  final int endRaw;
  MatchResult(this.cost, this.startRaw, this.endRaw);
}

MatchResult _bestSubstringMatch(String pattern, String text) {
  int bestCost = 999;
  int bestStart = 0;
  int bestEnd = 0;

  List<int> rawIndices = [];
  String normalized = "";
  for (int i = 0; i < text.length; i++) {
    if (RegExp(r'[A-Z0-9]').hasMatch(text[i])) {
      normalized += text[i];
      rawIndices.add(i);
    }
  }

  if (normalized.length < 5) return MatchResult(999, 0, 0);

  for (int start = 0; start < normalized.length; start++) {
    int minLen = max(1, pattern.length - 3);
    int maxLen = min(normalized.length - start, pattern.length + 3);
    
    for (int len = minLen; len <= maxLen; len++) {
      int end = start + len;
      int cost = _levenshtein(pattern, normalized.substring(start, end));
      if (cost < bestCost) {
        bestCost = cost;
        bestStart = start;
        bestEnd = end;
      }
    }
  }

  if (bestCost == 999) return MatchResult(999, 0, 0);

  int actualRawStart = rawIndices[bestStart];
  int actualRawEnd = bestEnd > 0 ? rawIndices[bestEnd - 1] + 1 : 0;

  return MatchResult(bestCost, actualRawStart, actualRawEnd);
}

void main() {
  String rawText = '213515 -KTE-600 ASSY START';
  String barcode = '35150KTE600';
  
  var match = _bestSubstringMatch(barcode, rawText);
  print('Cost: ' + match.cost.toString());
  print('Start: ' + match.startRaw.toString());
  print('End: ' + match.endRaw.toString());
  
  if (match.cost <= 2) {
    String sr = rawText.substring(0, match.startRaw).replaceAll(RegExp(r'[^0-9]'), '').trim();
    String desc = rawText.substring(match.endRaw).replaceAll(RegExp(r'^[-\s\|]+'), '').trim();
    print('SR: ' + sr);
    print('DESC: ' + desc);
  }
}
