import re

with open('lib/features/scan_to_find/screens/scan_to_find_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove _SearchChip class
start_idx = content.find('class _SearchChip extends StatelessWidget {')
if start_idx != -1:
    # find the matching closing brace
    brace_count = 0
    end_idx = start_idx
    for i in range(start_idx, len(content)):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                end_idx = i + 1
                break
    
    content = content[:start_idx] + content[end_idx:]

with open('lib/features/scan_to_find/screens/scan_to_find_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Replaced successfully")
