import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'license.dart';

/// Map Play subscription product IDs -> our plan codes.
/// Create these as subscription products in the Play Console (one base plan each).
const Map<String, String> kSubProductIds = {
  'profinance_1m': '1M',
  'profinance_1y': '1Y',
  'profinance_2y': '2Y',
};

int _planDays(String code) {
  for (final p in kPlans) {
    if (p.code == code) return p.days;
  }
  return 30;
}

class BillingService extends ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  bool loading = false;
  String? error;
  List<ProductDetails> products = [];

  Future<void> init() async {
    try {
      available = await _iap.isAvailable();
      if (!available) return;
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e) {
        error = '$e';
        notifyListeners();
      });
      await refresh();
      await _iap.restorePurchases();
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!available) return;
    loading = true;
    notifyListeners();
    try {
      final resp = await _iap.queryProductDetails(kSubProductIds.keys.toSet());
      products = resp.productDetails
        ..sort((a, b) => _planDays(kSubProductIds[a.id] ?? '1M')
            .compareTo(_planDays(kSubProductIds[b.id] ?? '1M')));
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> buy(ProductDetails pd) async {
    final param = PurchaseParam(productDetails: pd);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() async {
    if (available) await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        final plan = kSubProductIds[p.productID];
        if (plan != null) {
          int start = DateTime.now().millisecondsSinceEpoch;
          final td = p.transactionDate;
          if (td != null) {
            final parsed = int.tryParse(td);
            if (parsed != null) start = parsed;
          }
          final expiry = (start ~/ 1000) + _planDays(plan) * 86400;
          await license.applyBillingPurchase(plan, expiry);
        }
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final billing = BillingService();
