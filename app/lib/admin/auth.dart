import 'package:flutter/foundation.dart';

import '../api/api.dart';

class AdminAuth extends ChangeNotifier {
  AdminAuth._() {
    Api.instance.onUnauthorized = expired;
  }

  static final AdminAuth instance = AdminAuth._();

  bool? loggedIn;
  String studioName = '';
  Future<bool>? _checking;

  Future<bool> check() {
    if (loggedIn != null) return Future.value(loggedIn);
    return _checking ??= () async {
      try {
        final me = await Api.instance.get('/api/auth/me') as Map<String, dynamic>;
        studioName = me['studioName'] as String? ?? '';
        loggedIn = true;
      } catch (_) {
        loggedIn = false;
      }
      _checking = null;
      notifyListeners();
      return loggedIn!;
    }();
  }

  Future<void> login(String email, String password) async {
    await Api.instance.post('/api/auth/login', {'email': email.trim(), 'password': password});
    loggedIn = null;
    await check();
  }

  Future<void> logout() async {
    try {
      await Api.instance.post('/api/auth/logout');
    } catch (_) {}
    loggedIn = false;
    notifyListeners();
  }

  void expired() {
    if (loggedIn == false) return;
    loggedIn = false;
    notifyListeners();
  }
}
