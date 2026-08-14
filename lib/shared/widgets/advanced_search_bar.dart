import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AdvancedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final VoidCallback onGoPressed;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  
  final String searchField;
  final ValueChanged<String?> onSearchFieldChanged;
  final List<String> searchFieldOptions;

  final String sortField;
  final ValueChanged<String?> onSortFieldChanged;
  final List<String> sortFieldOptions;

  final String sortOrder;
  final ValueChanged<String?> onSortOrderChanged;
  final List<String> sortOrderOptions;

  const AdvancedSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = 'Search catalog...',
    required this.onGoPressed,
    required this.onChanged,
    required this.onClear,
    required this.searchField,
    required this.onSearchFieldChanged,
    this.searchFieldOptions = const ['All Fields', 'Part No', 'Location', 'Description'],
    required this.sortField,
    required this.onSortFieldChanged,
    this.sortFieldOptions = const ['Part No', 'Location'],
    required this.sortOrder,
    required this.onSortOrderChanged,
    this.sortOrderOptions = const ['Ascending', 'Descending'],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onSubmitted: (_) => onGoPressed(),
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 20),
                              onPressed: onClear,
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: onGoPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: const Text(
                    'Go',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: _buildDropdownColumn(
                  label: 'Search Field',
                  value: searchField,
                  options: searchFieldOptions,
                  onChanged: onSearchFieldChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: _buildDropdownColumn(
                  label: 'Sort Field',
                  value: sortField,
                  options: sortFieldOptions,
                  onChanged: onSortFieldChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: _buildDropdownColumn(
                  label: 'Order',
                  value: sortOrder,
                  options: sortOrderOptions,
                  onChanged: onSortOrderChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownColumn({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
              onChanged: onChanged,
              items: options.map<DropdownMenuItem<String>>((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
