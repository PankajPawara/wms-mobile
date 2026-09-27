import re

with open('lib/features/scan_to_find/screens/scan_to_find_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add the helper method
helper = '''
  String _formatLocation(String? loc) {
    if (loc == null || loc.trim().isEmpty) return 'No Location';
    if (loc.trim().toLowerCase() == 'location not defined') return 'No Location';
    return loc;
  }
'''
if '_formatLocation' not in content:
    content = content.replace('bool _isManualSearching = false;', 'bool _isManualSearching = false;\n' + helper)

# Replace 'location': match.location,
content = re.sub(r"'location': match\.location,", r"'location': _formatLocation(match.location),", content)
content = re.sub(r"'locationLabel': 'Location: \$\{match\.location\}',", r"'locationLabel': 'Location: ',", content)

# Replace 'location': product['location'] ?? '',
content = re.sub(r"'location': product\['location'\] \?\? '',", r"'location': _formatLocation(product['location']),", content)
content = re.sub(r"'locationLabel': 'Location: \$\{product\['location'\] \?\? ''\}',", r"'locationLabel': 'Location: ',", content)

# Replace 'location': matches.first.location,
content = re.sub(r"'location': matches\.first\.location,", r"'location': _formatLocation(matches.first.location),", content)

# Replace 'location': results.first.location,
content = re.sub(r"'location': results\.first\.location,", r"'location': _formatLocation(results.first.location),", content)

# Replace 'location': item.location,
content = re.sub(r"'location': item\.location,", r"'location': _formatLocation(item.location),", content)
content = re.sub(r"'locationLabel': 'Location: \$\{item\.location\}',", r"'locationLabel': 'Location: ',", content)

# Replace query['location'] in history tap
content = re.sub(r"'location': query\['location'\] \?\? '',", r"'location': _formatLocation(query['location']?.toString()),", content)
content = re.sub(r"'locationLabel': 'Location: \$\{query\['location'\] \?\? ''\}',", r"'locationLabel': 'Location: ',", content)

# Replace loc.location in _buildMultipleLocations
content = re.sub(r"Text\(\s*loc\.location,", r"Text(\n_formatLocation(loc.location),", content)

# Replace item.location in _buildManualSearch UI
content = re.sub(r"Text\(\s*item\.location,", r"Text(\n_formatLocation(item.location),", content)

with open('lib/features/scan_to_find/screens/scan_to_find_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Done')
