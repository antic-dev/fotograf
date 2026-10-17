import 'package:flutter/foundation.dart';

import '../api/api.dart';

class AdminAuth extends ChangeNotifier {
  AdminAuth._() {
    Api.instance.onUnauthorized = expired;
  }

  static final AdminAuth instance = AdminAuth._();

  bool? loggedIn;
  String email = '';
  String studioName = '';
  Future<bool>? _checking;

  Future<bool> check() {
    if (loggedIn != null) return Future.value(loggedIn);
    return _checking ??= () async {
      try {
        final me = await Api.instance.get('/api/auth/me') as Map<String, dynamic>;
        email = me['email'] as String? ?? '';
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

  Future<void> loginWithGoogle(String credential) async {
    await Api.instance.post('/api/auth/google', {'credential': credential});
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
