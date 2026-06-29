import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../picking/repositories/order_repository.dart';
import '../../../core/database/app_database.dart';

class CheckingListScreen extends ConsumerStatefulWidget {
  const CheckingListScreen({super.key});

  @override
  ConsumerState<CheckingListScreen> createState() => _CheckingListScreenState();
}

class _CheckingListScreenState extends ConsumerState<CheckingListScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final repo = ref.read(orderRepositoryProvider);
    await repo.syncOrdersFromServer();
    final orders = await repo.getLocalOrders(status: 'pending_checking');
    if (mounted) {
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Pending Verification'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('No orders pending verification', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(
                          order.customerName ?? 'Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Memo: #${order.memoNumber}\nLocation: ${order.customerLocation ?? "-"}',
                          style: const TextStyle(color: Colors.grey, height: 1.4),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primary),
                        onTap: () {
                          context.push('/order/${order.id}').then((_) => _loadOrders());
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
