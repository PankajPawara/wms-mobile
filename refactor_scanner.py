import re

with open('lib/features/scan_to_find/screens/scan_to_find_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import
if 'advanced_search_bar.dart' not in content:
    content = content.replace("import '../../../core/utils/scan_feedback.dart';", "import '../../../core/utils/scan_feedback.dart';\nimport '../../../shared/widgets/advanced_search_bar.dart';")

# 2. Update state variables
content = content.replace("String _searchByField = 'Part No';", "String _searchByField = 'All Fields';\n  String _sortField = 'Part No';\n  String _sortOrder = 'Ascending';")

# 3. Update _performManualSearch
old_search = '''    List<InventoryData> results;
    if (_searchByField == 'Location') {
      results = await (db.select(db.inventory)
            ..where((t) => t.location.upper().like('%%')))
          .get();
    } else if (_searchByField == 'Description') {
      results = await (db.select(db.inventory)
            ..where((t) => t.description.upper().like('%%')))
          .get();
    } else {
      results = await (db.select(db.inventory)
            ..where((t) =>
                t.partNo.upper().like('%%') | t.barcode.like('%%')))
          .get();
    }'''

new_search = '''    var selectStmt = db.select(db.inventory);
    
    if (_searchByField == 'Location') {
      selectStmt.where((t) => t.location.upper().like('%\%'));
    } else if (_searchByField == 'Description') {
      selectStmt.where((t) => t.description.upper().like('%\%'));
    } else if (_searchByField == 'Part No') {
      selectStmt.where((t) => t.partNo.upper().like('%\%') | t.barcode.like('%\%'));
    } else {
      selectStmt.where((t) => t.partNo.upper().like('%\%') | t.barcode.like('%\%') | t.location.upper().like('%\%') | t.description.upper().like('%\%'));
    }
    
    if (_sortField == 'Location') {
      selectStmt.orderBy([(t) => OrderingTerm(expression: t.location, mode: _sortOrder == 'Descending' ? OrderingMode.desc : OrderingMode.asc)]);
    } else {
      selectStmt.orderBy([(t) => OrderingTerm(expression: t.partNo, mode: _sortOrder == 'Descending' ? OrderingMode.desc : OrderingMode.asc)]);
    }
    
    List<InventoryData> results = await selectStmt.get();'''

content = content.replace(old_search, new_search)

# 4. Replace _buildManualSearch UI
old_ui_start = '''          children: [
            Container(
              color: AppColors.primary,
              child: Padding('''
old_ui_end = '''              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),'''

# Extract the block to replace
pattern = re.compile(re.escape(old_ui_start) + r'.*?' + re.escape(old_ui_end), re.DOTALL)

new_ui = '''          children: [
            AdvancedSearchBar(
              controller: _manualController,
              focusNode: _manualFocusNode,
              onGoPressed: () {
                _manualFocusNode.unfocus();
              },
              onChanged: (val) {
                _manualSearchQuery = val;
                _performManualSearch();
              },
              onClear: () {
                _manualController.clear();
                setState(() {
                  _manualSearchQuery = '';
                  _performManualSearch();
                });
                _manualFocusNode.requestFocus();
              },
              searchField: _searchByField,
              onSearchFieldChanged: (val) {
                if (val != null) {
                  setState(() => _searchByField = val);
                  _performManualSearch();
                }
              },
              sortField: _sortField,
              onSortFieldChanged: (val) {
                if (val != null) {
                  setState(() => _sortField = val);
                  _performManualSearch();
                }
              },
              sortOrder: _sortOrder,
              onSortOrderChanged: (val) {
                if (val != null) {
                  setState(() => _sortOrder = val);
                  _performManualSearch();
                }
              },
            ),
            const Divider(height: 1, thickness: 1),'''

content = pattern.sub(new_ui, content)

with open('lib/features/scan_to_find/screens/scan_to_find_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Replaced successfully")
