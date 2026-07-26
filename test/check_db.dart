import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main() {
  // Try to open the database file
  final dbPath = 'assets/database/inventory.db';
  print('Opening $dbPath');
  final db = sqlite3.open(dbPath);
  
  final result = db.select('SELECT * FROM inventory LIMIT 5;');
  for (final row in result) {
    print(row);
  }
  
  db.dispose();
}
