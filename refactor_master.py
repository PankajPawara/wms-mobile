import re

with open('lib/features/parts_master/screens/parts_master_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import
if 'advanced_search_bar.dart' not in content:
    content = content.replace("import '../../../features/auth/providers/auth_provider.dart';", "import '../../../features/auth/providers/auth_provider.dart';\nimport '../../../shared/widgets/advanced_search_bar.dart';")

# 2. Add State variables
if '_searchByField' not in content:
    content = content.replace("final TextEditingController _searchCtrl = TextEditingController();", "final TextEditingController _searchCtrl = TextEditingController();\n  String _searchByField = 'All Fields';\n  String _sortField = 'Part No';\n  String _sortOrder = 'Ascending';")

# 3. Replace _applyFilter
old_filter = '''  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allItems
          : _allItems.where((p) {
              return (p.partNo.toLowerCase().contains(q)) ||
                  (p.description?.toLowerCase().contains(q) ?? false) ||
                  (p.location?.toLowerCase().contains(q) ?? false);
            }).toList();
    });
  }'''

new_filter = '''  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      var filtered = q.isEmpty
          ? List<PartsMasterData>.from(_allItems)
          : _allItems.where((p) {
              if (_searchByField == 'Location') {
                return p.location?.toLowerCase().contains(q) ?? false;
              } else if (_searchByField == 'Description') {
                return p.description?.toLowerCase().contains(q) ?? false;
              } else if (_searchByField == 'Part No') {
                return p.partNo.toLowerCase().contains(q);
              } else {
                return (p.partNo.toLowerCase().contains(q)) ||
                    (p.description?.toLowerCase().contains(q) ?? false) ||
                    (p.location?.toLowerCase().contains(q) ?? false);
              }
            }).toList();

      if (_sortField == 'Location') {
        filtered.sort((a, b) {
          final locA = a.location?.toLowerCase() ?? '';
          final locB = b.location?.toLowerCase() ?? '';
          return _sortOrder == 'Descending' ? locB.compareTo(locA) : locA.compareTo(locB);
        });
      } else {
        filtered.sort((a, b) {
          final pA = a.partNo.toLowerCase();
          final pB = b.partNo.toLowerCase();
          return _sortOrder == 'Descending' ? pB.compareTo(pA) : pA.compareTo(pB);
        });
      }
      _filtered = filtered;
    });
  }'''

content = content.replace(old_filter, new_filter)

# 4. Replace UI
old_ui_start = '''          // Search bar
          Container(
            color: AppColors.surface,'''
old_ui_end = '''              ),
            ),

            // Stats bar'''

pattern = re.compile(re.escape(old_ui_start) + r'.*?' + re.escape(old_ui_end), re.DOTALL)

new_ui = '''          // Search bar
          AdvancedSearchBar(
            controller: _searchCtrl,
            onGoPressed: () => FocusScope.of(context).unfocus(),
            onChanged: (_) {}, // handled by listener
            onClear: () {
              _searchCtrl.clear();
              _applyFilter();
            },
            searchField: _searchByField,
            onSearchFieldChanged: (val) {
              if (val != null) setState(() { _searchByField = val; _applyFilter(); });
            },
            sortField: _sortField,
            onSortFieldChanged: (val) {
              if (val != null) setState(() { _sortField = val; _applyFilter(); });
            },
            sortOrder: _sortOrder,
            onSortOrderChanged: (val) {
              if (val != null) setState(() { _sortOrder = val; _applyFilter(); });
            },
          ),
          const Divider(height: 1, thickness: 1),

            // Stats bar'''

content = pattern.sub(new_ui, content)

with open('lib/features/parts_master/screens/parts_master_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Replaced successfully")
