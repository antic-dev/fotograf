import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api.dart';

/// Javlja otvorenim admin stranicama da su se podaci promenili (nov projekat,
/// brisanje, otpremljena fotografija...), da prikaz nikad ne bude zastareo.
class AdminRefresh extends ChangeNotifier {
  AdminRefresh._() {
    Api.instance.onMutation = (path) {
      if (path.startsWith('/api/admin/')) changed();
    };
  }

  static final AdminRefresh instance = AdminRefresh._();

  Timer? _debounce;

  /// Više promena zaredom (npr. 100 otpremljenih fotografija) → jedno osvežavanje.
  void changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), notifyListeners);
  }
}
