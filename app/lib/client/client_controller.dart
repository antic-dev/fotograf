import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/models.dart';

/// Stanje galerije za klijenta. Svaki dodir se odmah prikazuje (optimistično),
/// a u pozadini se čuva na serveru — klijent nikada ne mora da pritisne "Sačuvaj".
class ClientController extends ChangeNotifier {
  ClientController(this.token);

  final String token;
  final Api _api = Api.instance;

  bool loading = true;
  Object? error;
  String studioName = '';
  ClientProject? project;
  List<Photo> photos = [];
  final Map<String, OrderItem> _items = {};
  final List<String> _order = [];
  String status = 'draft';
  String name = '';
  String phone = '';
  String note = '';
  int? submittedAt;
  bool onlySelected = false;
  int _pending = 0;

  /// Svi zahtevi za čuvanje idu strogo jedan za drugim. Ovo je bitno pri prvom
  /// ulasku: server tek iz prvog odgovora postavlja kolačić posetioca, pa bi
  /// dva paralelna zahteva napravila dva različita posetioca.
  Future<void> _chain = Future.value();

  String get _base => '/api/s/$token';
  String thumbUrl(String id) => '$_base/photos/$id/thumb';
  String previewUrl(String id) => '$_base/photos/$id/preview';

  bool get saving => _pending > 0;
  bool get canEdit => (project?.canSelect ?? false) && status == 'draft';
  bool get submitted => status != 'draft';
  int get selectedCount => _items.length;
  int get copies => _items.values.fold(0, (a, b) => a + b.quantity);
  bool isSelected(String id) => _items.containsKey(id);
  OrderItem? item(String id) => _items[id];

  /// Izabrane fotografije redom kojim su izabrane.
  List<Photo> get selectedPhotos {
    final byId = {for (final p in photos) p.id: p};
    return [for (final id in _order) if (byId[id] != null && _items.containsKey(id)) byId[id]!];
  }

  List<Photo> get visiblePhotos => onlySelected ? photos.where((p) => isSelected(p.id)).toList() : photos;

  int indexOf(String id) => photos.indexWhere((p) => p.id == id);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.get(_base) as Map<String, dynamic>;
      studioName = data['studioName'] as String? ?? '';
      project = ClientProject.fromJson(data['project'] as Map<String, dynamic>);
      photos = [for (final p in data['photos'] as List) Photo.fromJson(p as Map<String, dynamic>)];
      _applyOrder(ClientOrder.fromJson(data['order'] as Map<String, dynamic>));
    } catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  void _applyOrder(ClientOrder o) {
    status = o.status;
    if (o.name.isNotEmpty) name = o.name;
    if (o.phone.isNotEmpty) phone = o.phone;
    if (o.note.isNotEmpty) note = o.note;
    submittedAt = o.submittedAt;
    _items
      ..clear()
      ..addEntries(o.items.map((i) => MapEntry(i.photoId, i)));
    _order
      ..removeWhere((id) => !_items.containsKey(id))
      ..addAll(o.items.map((i) => i.photoId).where((id) => !_order.contains(id)));
  }

  void setOnlySelected(bool v) {
    onlySelected = v;
    notifyListeners();
  }

  /// Vraća poruku za korisnika ako izbor nije moguć, inače null.
  String? toggle(String photoId) {
    if (!canEdit) return null;
    if (isSelected(photoId)) {
      _items.remove(photoId);
      _order.remove(photoId);
      notifyListeners();
      _sync(() => _api.delete('$_base/selection/$photoId'));
      return null;
    }
    final max = project?.maxPhotos;
    if (max != null && selectedCount >= max) {
      return 'Možete izabrati najviše $max fotografija. Ako želite ovu, prvo uklonite neku drugu.';
    }
    _items[photoId] = OrderItem(photoId: photoId, quantity: 1);
    _order.add(photoId);
    notifyListeners();
    _sync(() => _api.put('$_base/selection/$photoId'));
    return null;
  }

  /// Menja broj primeraka (1–99). Format je isti za sve fotografije.
  void setQuantity(String photoId, int quantity) {
    final current = _items[photoId];
    if (current == null || !canEdit || quantity < 1 || quantity > 99) return;
    _items[photoId] = current.copyWith(quantity: quantity);
    notifyListeners();
    _sync(() => _api.put('$_base/selection/$photoId', {'quantity': quantity}));
  }

  /// Greške pri čuvanju se prijavljuju preko ovog callback-a.
  void Function(String message)? onSyncError;

  void _sync(Future<dynamic> Function() call) {
    _pending++;
    notifyListeners();
    _chain = _chain.then((_) async {
      try {
        await call();
      } catch (e) {
        onSyncError?.call(e is ApiException ? e.message : 'Izbor nije sačuvan. Proverite internet vezu.');
        await _resync();
      } finally {
        _pending--;
        notifyListeners();
      }
    });
  }

  Future<void> _resync() async {
    try {
      final data = await _api.get(_base) as Map<String, dynamic>;
      project = ClientProject.fromJson(data['project'] as Map<String, dynamic>);
      _applyOrder(ClientOrder.fromJson(data['order'] as Map<String, dynamic>));
    } catch (_) {}
  }

  Future<void> _flush() => _chain;

  Future<void> submit({required String name, required String phone, required String note}) async {
    await _flush();
    final data = await _api.post('$_base/submit', {'name': name, 'phone': phone, 'note': note});
    this.name = name;
    this.phone = phone;
    this.note = note;
    _applyOrder(ClientOrder.fromJson(data as Map<String, dynamic>));
    notifyListeners();
  }

  Future<void> reopen() async {
    final data = await _api.post('$_base/reopen');
    _applyOrder(ClientOrder.fromJson(data as Map<String, dynamic>));
    notifyListeners();
  }
}
