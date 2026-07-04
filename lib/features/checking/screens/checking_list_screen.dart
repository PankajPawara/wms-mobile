import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../picking/repositories/order_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/empty_state_placeholder.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadOrders,
                child: _orders.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                              height:
                                  MediaQuery.of(context).size.height * 0.15),
                          const EmptyStatePlaceholder(
                            icon: Icons.check_circle_outline_rounded,
                            title: 'No Pending Checking',
                            subtitle:
                                'All picked orders have been checked. Pull down to check for new assignments.',
                          ),
                        ],
                      )
                    : Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom + 64,
                        ),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _orders.length,
                          itemBuilder: (context, index) {
                            final order = _orders[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                title: Text(
                                  order.customerName ?? 'Customer',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'Memo: #${order.memoNumber}\nLocation: ${order.customerLocation ?? "-"}',
                                  style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.4),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: AppColors.primary),
                                onTap: () async {
                                  await context.push('/order/${order.id}');
                                  if (mounted) _loadOrders();
                                },
                              ),
                            );
                          },
                        ),
                      ),
              ),
      ),
    );
  }
}
