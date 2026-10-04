import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'orders_controller.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ordersControllerProvider.notifier).load());
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        ref.read(ordersControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.read(ordersControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text('My Orders')),
      body: orders.when(
        data: (list) => ListView(
          controller: _scroll,
          children: [
            for (final order in list)
              GestureDetector(
                onTap: () {
                  ref.read(selectedOrderProvider.notifier).state = order;
                  context.push('/order-details', extra: order);
                },
                child: Container(
                  height: 60,
                  color: Colors.blue[50],
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    order.title,
                    style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
                  ),
                ),
              ),
          ],
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        loading: () => Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
