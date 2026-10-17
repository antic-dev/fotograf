// Imena polja moraju tačno odgovarati Google JS API-ju.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// Google Identity Services ("Sign in with Google") — minimalni JS interop.

extension type _IdConfig._(JSObject _) implements JSObject {
  external factory _IdConfig({
    String client_id,
    JSFunction callback,
    String nonce,
    bool auto_select,
    bool cancel_on_tap_outside,
    String ux_mode,
    bool itp_support,
    String context,
  });
}

extension type _ButtonConfig._(JSObject _) implements JSObject {
  external factory _ButtonConfig({
    String type,
    String theme,
    String size,
    String text,
    String shape,
    String logo_alignment,
    int width,
    String locale,
  });
}

extension type _CredentialResponse._(JSObject _) implements JSObject {
  external String? get credential;
}

@JS('google.accounts.id.initialize')
external void _initialize(_IdConfig config);

@JS('google.accounts.id.renderButton')
external void _renderButton(web.HTMLElement parent, _ButtonConfig options);

Future<void>? _loading;

Future<void> _loadScript() => _loading ??= () {
      final c = Completer<void>();
      final s = web.HTMLScriptElement()
        ..src = 'https://accounts.google.com/gsi/client'
        ..async = true
        ..defer = true;
      s.onload = (web.Event _) {
        c.complete();
      }.toJS;
      s.onerror = (web.Event _) {
        _loading = null;
        c.completeError(StateError('Google prijava nije dostupna. Proverite internet vezu.'));
      }.toJS;
      web.document.head!.append(s);
      return c.future;
    }();

/// Zvanično Google dugme. Kada se korisnik prijavi, poziva [onCredential]
/// sa potpisanim ID tokenom koji server proverava.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, required this.clientId, required this.nonce, required this.onCredential});

  final String clientId;
  final String nonce;
  final void Function(String credential) onCredential;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _loadScript().then((_) {
      _initialize(_IdConfig(
        client_id: widget.clientId,
        nonce: widget.nonce,
        auto_select: false,
        cancel_on_tap_outside: true,
        ux_mode: 'popup',
        itp_support: true,
        context: 'signin',
        callback: (_CredentialResponse r) {
          final c = r.credential;
          if (c != null) widget.onCredential(c);
        }.toJS,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(snap.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.red));
        }
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
        }
        return SizedBox(
          width: 300,
          height: 48,
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            onElementCreated: (Object el) {
              final div = el as web.HTMLElement;
              div.style
                ..display = 'flex'
                ..justifyContent = 'center';
              _renderButton(
                div,
                _ButtonConfig(type: 'standard', theme: 'filled_black', size: 'large', text: 'signin_with', shape: 'pill', logo_alignment: 'left', width: 300, locale: 'sr'),
              );
            },
          ),
        );
      },
    );
  }
}
