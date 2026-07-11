import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  final env = File('.env').readAsStringSync();
  final apiKey = env.split('=')[1].trim();
  print('Key starts with: \');
  final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
  try {
    final response = await model.generateContent([Content.text('Hello')]);
    print('gemini-1.5-flash SUCCESS: \');
  } catch(e) {
    print('gemini-1.5-flash ERROR: \');
  }
  
  final model2 = GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);
  try {
    final response = await model2.generateContent([Content.text('Hello')]);
    print('gemini-1.5-flash-latest SUCCESS: \');
  } catch(e) {
    print('gemini-1.5-flash-latest ERROR: \');
  }
  
  final model3 = GenerativeModel(model: 'gemini-pro-vision', apiKey: apiKey);
  try {
    final response = await model3.generateContent([Content.text('Hello')]);
    print('gemini-pro-vision SUCCESS: \');
  } catch(e) {
    print('gemini-pro-vision ERROR: \');
  }
}
