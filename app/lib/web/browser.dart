import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

const _acceptedImages = 'image/jpeg,image/png,image/webp,image/tiff,.jpg,.jpeg,.png,.webp,.tif,.tiff';

/// Otvara izbor fajlova (na telefonu nudi galeriju/kameru, na računaru folder).
Future<List<web.File>> pickImages() {
  final completer = Completer<List<web.File>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = _acceptedImages
    ..style.display = 'none';
  web.document.body!.append(input);
  input.onchange = (web.Event _) {
    final files = <web.File>[];
    final list = input.files;
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        files.add(list.item(i)!);
      }
    }
    input.remove();
    if (!completer.isCompleted) completer.complete(files);
  }.toJS;
  input.addEventListener('cancel', (web.Event _) {
    input.remove();
    if (!completer.isCompleted) completer.complete(const []);
  }.toJS);
  input.click();
  return completer.future;
}

bool isImageFile(web.File f) {
  final n = f.name.toLowerCase();
  return f.type.startsWith('image/') || RegExp(r'\.(jpe?g|png|webp|tiff?|heic)$').hasMatch(n);
}

class UploadHandle {
  UploadHandle(this._xhr, this.done);
  final web.XMLHttpRequest _xhr;
  final Future<String> done;
  void cancel() => _xhr.abort();
}

class UploadError implements Exception {
  UploadError(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// Otpremanje sa praćenjem napretka. Fajl ide direktno iz pregledača
/// (bez učitavanja u memoriju aplikacije).
UploadHandle uploadFile(String url, web.File file, void Function(double progress) onProgress) {
  final xhr = web.XMLHttpRequest();
  final completer = Completer<String>();
  xhr.open('POST', url);
  xhr.setRequestHeader('X-Fotograf', '1');
  xhr.setRequestHeader('Content-Type', 'application/octet-stream');
  xhr.upload.onprogress = (web.ProgressEvent e) {
    if (e.lengthComputable && e.total > 0) onProgress(e.loaded / e.total);
  }.toJS;
  xhr.onload = (web.Event _) {
    if (xhr.status >= 200 && xhr.status < 300) {
      completer.complete(xhr.responseText);
    } else {
      var msg = 'Greška ${xhr.status}';
      final m = RegExp(r'"error"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(xhr.responseText);
      if (m != null) msg = m.group(1)!.replaceAll(r'\"', '"');
      completer.completeError(UploadError(msg, status: xhr.status));
    }
  }.toJS;
  xhr.onerror = (web.Event _) {
    if (!completer.isCompleted) completer.completeError(UploadError('Veza je prekinuta.'));
  }.toJS;
  xhr.onabort = (web.Event _) {
    if (!completer.isCompleted) completer.completeError(UploadError('Otkazano.'));
  }.toJS;
  xhr.send(file);
  return UploadHandle(xhr, completer.future);
}

/// Deli link preko sistemskog menija (Viber, WhatsApp, SMS, Mejl...).
/// Vraća false ako pregledač to ne podržava (tada kopiramo link).
Future<bool> shareLink({required String title, required String text, required String url}) async {
  final nav = web.window.navigator;
  if (!nav.has('share')) return false;
  try {
    await nav.share(web.ShareData(title: title, text: text, url: url)).toDart;
    return true;
  } catch (e) {
    // Korisnik je zatvorio meni — to nije greška.
    return e.toString().contains('AbortError');
  }
}

Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

void openInNewTab(String url) => web.window.open(url, '_blank', 'noopener,noreferrer');

void navigateTo(String url) => web.window.location.href = url;

/// Pokreće preuzimanje fajla sa našeg servera.
void download(String url) {
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = ''
    ..rel = 'noopener';
  web.document.body!.append(a);
  a.click();
  a.remove();
}

String mailtoUrl({required String to, required String subject, required String body}) =>
    'mailto:${Uri.encodeComponent(to)}?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';

/// Prevlačenje fajlova sa računara (drag & drop) bilo gde na stranicu.
class FileDropListener {
  FileDropListener({required this.onFiles, required this.onDragChange});

  final void Function(List<web.File> files) onFiles;
  final void Function(bool dragging) onDragChange;

  JSFunction? _over;
  JSFunction? _leave;
  JSFunction? _drop;
  int _depth = 0;

  void attach() {
    _over = (web.DragEvent e) {
      e.preventDefault();
      if (_depth == 0) {
        _depth = 1;
        onDragChange(true);
      }
    }.toJS;
    _leave = (web.DragEvent e) {
      if (e.relatedTarget == null) {
        _depth = 0;
        onDragChange(false);
      }
    }.toJS;
    _drop = (web.DragEvent e) {
      e.preventDefault();
      _depth = 0;
      onDragChange(false);
      final list = e.dataTransfer?.files;
      if (list == null) return;
      final files = <web.File>[];
      for (var i = 0; i < list.length; i++) {
        final f = list.item(i)!;
        if (isImageFile(f)) files.add(f);
      }
      if (files.isNotEmpty) onFiles(files);
    }.toJS;
    web.window.addEventListener('dragover', _over);
    web.window.addEventListener('dragleave', _leave);
    web.window.addEventListener('drop', _drop);
  }

  void detach() {
    if (_over != null) web.window.removeEventListener('dragover', _over);
    if (_leave != null) web.window.removeEventListener('dragleave', _leave);
    if (_drop != null) web.window.removeEventListener('drop', _drop);
  }
}

/// Upozorenje pre zatvaranja stranice dok otpremanje traje.
class LeaveGuard {
  JSFunction? _fn;

  void enable() {
    if (_fn != null) return;
    _fn = (web.BeforeUnloadEvent e) {
      e.preventDefault();
    }.toJS;
    web.window.addEventListener('beforeunload', _fn);
  }

  void disable() {
    if (_fn == null) return;
    web.window.removeEventListener('beforeunload', _fn);
    _fn = null;
  }
}
