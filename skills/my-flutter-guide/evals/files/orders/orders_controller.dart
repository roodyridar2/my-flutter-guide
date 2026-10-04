import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'order.dart';

final ordersRepositoryProvider = Provider((ref) => OrdersRepository());

class OrdersRepository {
  final _dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

  Future<List<Order>?> getOrders(int page) async {
    try {
      final res = await _dio.get('/orders', queryParameters: {'page': page});
      return (res.data as List).map((e) => Order.fromJson(e)).toList();
    } catch (e) {
      print('getOrders error: $e');
      return null;
    }
  }
}

class OrdersController extends AsyncNotifier<List<Order>> {
  int _page = 1;

  @override
  Future<List<Order>> build() async {
    return await load();
  }

  Future<List<Order>> load() async {
    _page = 1;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final data = await ref.read(ordersRepositoryProvider).getOrders(1);
      if (data == null) throw Exception('Failed to load orders');
      return data;
    });
    return state.value ?? [];
  }

  Future<void> loadMore() async {
    _page++;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final more = await ref.read(ordersRepositoryProvider).getOrders(_page);
      if (more == null) throw Exception('Failed to load more orders');
      return [...?state.value, ...more];
    });
  }
}

final ordersControllerProvider =
    AsyncNotifierProvider<OrdersController, List<Order>>(OrdersController.new);

final selectedOrderProvider = StateProvider<Order?>((ref) => null);
