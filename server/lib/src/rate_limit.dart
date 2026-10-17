/// Jednostavan ograničivač broja zahteva (fiksni prozor) po ključu, npr. IP adresi.
class RateLimiter {
  final Map<String, _Window> _windows = {};
  int _ops = 0;

  /// Vraća `true` ako je zahtev dozvoljen.
  bool allow(String key, int max, Duration window) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (++_ops % 1000 == 0) _windows.removeWhere((_, w) => w.resetAt < now);
    final w = _windows[key];
    if (w == null || w.resetAt < now) {
      _windows[key] = _Window(now + window.inMilliseconds, 1);
      return true;
    }
    if (w.count >= max) return false;
    w.count++;
    return true;
  }
}

class _Window {
  _Window(this.resetAt, this.count);
  final int resetAt;
  int count;
}
