import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser {
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static bool get isAuthenticated {
    try {
      return currentUser != null;
    } catch (_) {
      return false;
    }
  }

  // --- AUTHENTICATION ---
  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static Future<void> resetPasswordForEmail(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  // --- PROFILES & DRIVER LOCATION ---
  static Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    return await client
        .from('profiles')
        .select('id, full_name, phone, address, role, avatar_url, latitude, longitude, updated_at')
        .eq('id', userId)
        .maybeSingle();
  }

  static Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null || currentUserId != driverId) return;

    final isoNow = DateTime.now().toIso8601String();

    try {
      await client.from('profiles').update({
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': isoNow,
      }).eq('id', driverId);
    } catch (e) {
      debugPrint('Error updating profiles location: $e');
    }

    try {
      await client.from('driver_locations').upsert({
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': isoNow,
      }, onConflict: 'driver_id');
    } catch (e) {
      debugPrint('Error updating driver_locations table: $e');
    }
  }

  static Future<void> updateFcmToken(String token) async {
    final user = currentUser;
    if (user == null || token.trim().isEmpty) return;

    try {
      await client.from('profiles').update({
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (e) {
      debugPrint('Error updating FCM push token: $e');
    }
  }

  // --- DELIVERIES & ORDERS ---
  static Future<List<Map<String, dynamic>>> fetchDeliveries(String driverId) async {
    final response = await client
        .from('deliveries')
        .select('*, orders(*, order_items(*), profiles:customer_id(*))')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);
    
    final deliveries = List<Map<String, dynamic>>.from(response);

    for (var d in deliveries) {
      final order = d['orders'];
      if (order is Map<String, dynamic>) {
        final orderId = order['id']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          try {
            final paymentRecord = await client
                .from('payments')
                .select('method, status')
                .eq('order_id', orderId)
                .maybeSingle();
            if (paymentRecord != null) {
              final method = paymentRecord['method']?.toString();
              if (method != null && method.isNotEmpty) {
                order['payment_method'] = method;
                d['payment_method'] = method;
              }
            }
          } catch (_) {}
        }

        // Support direct embedded profiles or fallback to manual query if needed
        var profile = order['profiles'];
        
        if (profile == null) {
          final customerId = order['customer_id']?.toString();
          if (customerId != null && customerId.isNotEmpty) {
            try {
              profile = await client
                  .from('profiles')
                  .select('full_name, phone, address, latitude, longitude')
                  .eq('id', customerId)
                  .maybeSingle();
            } catch (_) {}
          }
        }

        if (profile != null && profile is Map<String, dynamic>) {
          order['profiles'] = profile;
          order['customer'] = profile;
          order['customer_name'] = profile['full_name'];
          
          if (profile['phone'] != null && profile['phone'].toString().isNotEmpty) {
            order['customer_phone'] = profile['phone'];
          }
          
          // Robust address extraction
          final String? orderAddr = order['delivery_address']?.toString();
          final String? profileAddr = profile['address']?.toString();
          
          bool isInvalid(String? s) {
            if (s == null) return true;
            final trimmed = s.trim();
            return trimmed.isEmpty || trimmed == 'N/A' || trimmed == '—' || trimmed == '-' || trimmed == '–';
          }

          if (isInvalid(orderAddr)) {
            if (!isInvalid(profileAddr)) {
              order['delivery_address'] = profileAddr;
            } else {
              order['delivery_address'] = 'Address not specified';
            }
          }
        }
      }
    }

    return deliveries;
  }

  // Realtime subscription for driver deliveries & orders
  static RealtimeChannel subscribeToDeliveries(String driverId, Function(String eventType, Map<String, dynamic>? payload) onUpdate) {
    final channel = client.channel('driver-updates-$driverId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'deliveries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: driverId,
      ),
      callback: (payload) {
        onUpdate('deliveries', payload.newRecord);
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        onUpdate('orders', payload.newRecord);
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'order_messages',
      callback: (payload) {
        onUpdate('order_messages', payload.newRecord);
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: driverId,
      ),
      callback: (payload) {
        onUpdate('notifications', payload.newRecord);
      },
    );

    channel.subscribe();
    return channel;
  }

  static RealtimeChannel subscribeToReviews(String driverId, Function(Map<String, dynamic>? newRecord) onUpdate) {
    final channel = client.channel('driver-reviews-$driverId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'reviews',
      callback: (payload) {
        onUpdate(payload.newRecord);
      },
    );
    channel.subscribe();
    return channel;
  }

  static Future<void> removeChannel(RealtimeChannel channel) async {
    await client.removeChannel(channel);
  }

  // Authoritative Delivery Status Update via public.driver_update_delivery_status
  static Future<bool> updateDeliveryStatus(String deliveryId, String status, {String? currentStatus}) async {
    final newStatus = status.toLowerCase();

    // Canonical status transition validation
    if (currentStatus != null && currentStatus.isNotEmpty) {
      final curr = currentStatus.toLowerCase();
      bool isValid = false;
      if (curr == 'assigned' && newStatus == 'accepted') {
        isValid = true;
      } else if (curr == 'accepted' && newStatus == 'out_for_delivery') {
        isValid = true;
      } else if (curr == 'out_for_delivery' && newStatus == 'delivered') {
        isValid = true;
      }

      if (!isValid) {
        throw Exception('Invalid delivery status transition from $curr to $newStatus');
      }
    }

    try {
      await client.rpc('driver_update_delivery_status', params: {
        'delivery_id': deliveryId,
        'status': newStatus,
      });
      return true;
    } catch (e) {
      debugPrint('RPC driver_update_delivery_status error: $e, falling back to direct table update');
      try {
        final Map<String, dynamic> deliveryUpdates = {
          'status': newStatus,
          if (newStatus == 'accepted') 'accepted_at': DateTime.now().toIso8601String(),
          if (newStatus == 'out_for_delivery') 'started_at': DateTime.now().toIso8601String(),
          if (newStatus == 'delivered') 'delivered_at': DateTime.now().toIso8601String(),
        };

        final deliveryRecord = await client
            .from('deliveries')
            .update(deliveryUpdates)
            .eq('id', deliveryId)
            .select('order_id')
            .maybeSingle();

        if (deliveryRecord != null && deliveryRecord['order_id'] != null) {
          final orderId = deliveryRecord['order_id'].toString();
          await client
              .from('orders')
              .update({'status': newStatus})
              .eq('id', orderId);
        }

        return true;
      } catch (fallbackError) {
        debugPrint('Direct update fallback error: $fallbackError');
        rethrow;
      }
    }
  }

  // --- STORAGE & FULFILLMENT (POD PHOTO & SIGNATURE) ---
  static Future<String> uploadPodPhoto({
    required String deliveryId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final filePath = 'pod/$deliveryId/pod_$fileName';
    await client.storage.from('pod').uploadBinary(
      filePath,
      bytes,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
    );

    final signedUrl = await client.storage.from('pod').createSignedUrl(filePath, 86400 * 365);
    return signedUrl;
  }

  static Future<String> uploadSignature({
    required String deliveryId,
    required Uint8List bytes,
  }) async {
    final filePath = 'signatures/$deliveryId/sig.png';
    await client.storage.from('pod').uploadBinary(
      filePath,
      bytes,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
    );

    final signedUrl = await client.storage.from('pod').createSignedUrl(filePath, 86400 * 365);
    return signedUrl;
  }

  static Future<void> updateFulfillment({
    required String deliveryId,
    String? podUrl,
    String? signatureData,
  }) async {
    final Map<String, dynamic> updates = {};
    if (podUrl != null && podUrl.isNotEmpty) {
      updates['pod_image_url'] = podUrl;
    }
    if (signatureData != null && signatureData.isNotEmpty) {
      updates['signature_data'] = signatureData;
    }

    if (updates.isNotEmpty) {
      await client.from('deliveries').update(updates).eq('id', deliveryId);
    }
  }

  // --- PAYMENTS ---
  static Future<void> recordPayment({
    required String orderId,
    required double amount,
    required String paymentMethod,
  }) async {
    final driverId = currentUser?.id;
    if (driverId == null || driverId.isEmpty) {
      throw Exception('Driver not authenticated');
    }

    // 1. Verify current driver is assigned to order through deliveries
    final delivery = await client
        .from('deliveries')
        .select('id')
        .eq('order_id', orderId)
        .eq('driver_id', driverId)
        .maybeSingle();

    if (delivery == null) {
      throw Exception('Order $orderId is not assigned to current driver');
    }

    // 2. Query order to verify total_amount
    final order = await client
        .from('orders')
        .select('id, total_amount, payment_status')
        .eq('id', orderId)
        .maybeSingle();

    if (order == null) {
      throw Exception('Order $orderId not found');
    }

    final orderTotal = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    if ((amount - orderTotal).abs() > 0.01) {
      throw Exception('Payment amount (₱$amount) does not match order total (₱$orderTotal)');
    }

    // 3. Idempotency check: check if paid payment already exists
    final existingPayment = await client
        .from('payments')
        .select('id, status')
        .eq('order_id', orderId)
        .eq('status', 'paid')
        .maybeSingle();

    if (existingPayment != null) {
      debugPrint('Payment for order $orderId is already recorded as paid.');
      return;
    }

    final methodVal = paymentMethod.toUpperCase().contains('GCASH') ? 'GCash' : 'COD';

    // 4. Insert payment
    await client.from('payments').insert({
      'order_id': orderId,
      'amount': orderTotal,
      'method': methodVal,
      'status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    });

    // 5. Update orders payment_status
    await client.from('orders').update({
      'payment_status': 'paid',
    }).eq('id', orderId);
  }

  // --- GALLON VERIFICATION & TRANSACTIONS ---
  static Future<Map<String, dynamic>?> verifyGallon(String gallonCode) async {
    // 1. Query gallons table directly by gallon_code
    final gallon = await client
        .from('gallons')
        .select('id, gallon_code, status, customer_id')
        .eq('gallon_code', gallonCode)
        .maybeSingle();

    if (gallon != null) return gallon;

    // 2. Query rfid_qr_records table by code where is_active = true
    final rfidRecord = await client
        .from('rfid_qr_records')
        .select('gallon_id')
        .eq('code', gallonCode)
        .eq('is_active', true)
        .maybeSingle();

    if (rfidRecord != null && rfidRecord['gallon_id'] != null) {
      final gallonId = rfidRecord['gallon_id'].toString();
      final resolvedGallon = await client
          .from('gallons')
          .select('id, gallon_code, status, customer_id')
          .eq('id', gallonId)
          .maybeSingle();
      if (resolvedGallon != null) {
        return resolvedGallon;
      }
    }

    return null;
  }

  static Future<List<Map<String, dynamic>>> fetchOrderGallonTransactions(String orderId) async {
    final response = await client
        .from('gallon_transactions')
        .select('*, gallons(id, gallon_code)')
        .eq('order_id', orderId);
    return List<Map<String, dynamic>>.from(response);
  }

  // Authoritative driver gallon action via public.driver_gallon_action
  static Future<void> driverGallonAction({
    required String gallonId,
    required String orderId,
    required String action, // 'borrow' or 'return'
  }) async {
    final canonicalAction = (action == 'borrow' || action == 'borrowed') ? 'borrow' : 'return';
    final gallonStatus = canonicalAction == 'borrow' ? 'borrowed' : 'available';

    // 1. Tawagin ang RPC function para sa logs/triggers ng database sa public schema
    try {
      await client.rpc('driver_gallon_action', params: {
        'p_gallon_id': gallonId,
        'p_order_id': orderId,
        'p_action': canonicalAction,
      });
    } catch (e) {
      debugPrint('RPC driver_gallon_action error: $e');
    }

    // 2. Direktang i-update ang status sa gallons table para pumasok agad sa Admin Side
    await client.from('gallons').update({
      'status': gallonStatus,
    }).eq('id', gallonId);
  }

  // --- REVIEWS & NOTIFICATIONS ---
  static Future<List<Map<String, dynamic>>> fetchDriverReviews(String driverId) async {
    final Set<Map<String, dynamic>> collectedReviews = {};

    try {
      // 1. Try querying reviews directly by driver_id
      final res1 = await client
          .from('reviews')
          .select('*, profiles:customer_id(full_name, phone)')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);
      for (var r in res1) {
        collectedReviews.add(Map<String, dynamic>.from(r));
      }
    } catch (e) {
      debugPrint('fetchDriverReviews by driver_id error: $e');
    }

    try {
      // 2. Query deliveries assigned to this driver to get order_ids and delivery_ids
      final deliveriesRes = await client
          .from('deliveries')
          .select('id, order_id')
          .eq('driver_id', driverId);

      final orderIds = <String>[];
      final deliveryIds = <String>[];
      for (var d in deliveriesRes) {
        if (d['order_id'] != null) orderIds.add(d['order_id'].toString());
        if (d['id'] != null) deliveryIds.add(d['id'].toString());
      }

      // 3. Query reviews by order_ids if any
      if (orderIds.isNotEmpty) {
        final resOrders = await client
            .from('reviews')
            .select('*, profiles:customer_id(full_name, phone)')
            .inFilter('order_id', orderIds);
        for (var r in resOrders) {
          collectedReviews.add(Map<String, dynamic>.from(r));
        }
      }

      // 4. Query reviews by delivery_ids if any
      if (deliveryIds.isNotEmpty) {
        final resDeliveries = await client
            .from('reviews')
            .select('*, profiles:customer_id(full_name, phone)')
            .inFilter('delivery_id', deliveryIds);
        for (var r in resDeliveries) {
          collectedReviews.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (e) {
      debugPrint('fetchDriverReviews by order/delivery ids error: $e');
    }

    // If still empty, try fetching all reviews as a fallback
    if (collectedReviews.isEmpty) {
      try {
        final allReviews = await client
            .from('reviews')
            .select('*, profiles:customer_id(full_name, phone)')
            .order('created_at', ascending: false)
            .limit(50);
        for (var r in allReviews) {
          collectedReviews.add(Map<String, dynamic>.from(r));
        }
      } catch (e) {
        debugPrint('fetchDriverReviews fallback all reviews error: $e');
      }
    }

    // Enrich profiles if missing
    final list = collectedReviews.toList();
    for (var r in list) {
      if (r['profiles'] == null && r['customer_id'] != null) {
        try {
          final custProfile = await client
              .from('profiles')
              .select('full_name, phone')
              .eq('id', r['customer_id'])
              .maybeSingle();
          if (custProfile != null) {
            r['profiles'] = custProfile;
          }
        } catch (_) {}
      }
    }

    // Sort by created_at descending
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0);
      final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  static Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final response = await client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<int> fetchUnreadNotificationCount(String userId) async {
    try {
      final response = await client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return (response as List).length;
    } catch (e) {
      debugPrint('Error fetching unread notification count: $e');
      return 0;
    }
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    await client.from('notifications').update({'is_read': true}).eq('id', notificationId);
  }

  // --- ORDER MESSAGING (order_messages) ---
  static Future<List<Map<String, dynamic>>> fetchMessages(String orderId) async {
    final response = await client
        .from('order_messages')
        .select('order_id, sender_id, message, created_at')
        .eq('order_id', orderId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> sendMessage({
    required String senderId,
    required String orderId,
    required String message,
  }) async {
    await client.from('order_messages').insert({
      'order_id': orderId,
      'sender_id': senderId,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
