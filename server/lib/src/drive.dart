import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import 'config.dart';
import 'crypto_util.dart';
import 'db.dart';
import 'google_id_token.dart';
import 'http_util.dart';

/// Najuži mogući pristup: aplikacija vidi SAMO fajlove koje je sama napravila
/// na tvom Google Drive-u. Ostatak tvog Drive-a joj je nevidljiv.
const driveScopes = ['openid', 'email', 'https://www.googleapis.com/auth/drive.file'];

const _folderMime = 'application/vnd.google-apps.folder';
const _rootFolderName = 'Fotograf';

class DriveNotConnected extends ApiError {
  DriveNotConnected()
      : super(503, 'Google Drive nije povezan. Otvorite Podešavanja i povežite nalog.', code: 'drive_not_connected');
}

/// Pristup Google Drive-u administratora. Struktura na Drive-u:
///
///   Fotograf/
///     2026-06-14 · Venčanje Ana i Marko/   ← jedan folder po projektu
///       IMG_0001.jpg
///       ...
class DriveStore {
  DriveStore({required this.config, required this.db, required this.box, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final Config config;
  final Db db;
  final SecretBox box;
  final http.Client _http;

  auth.AutoRefreshingAuthClient? _client;
  drive.DriveApi? _api;

  bool get connected => db.setting('drive_refresh_token') != null;
  String? get connectedEmail => db.setting('drive_email');

  drive.DriveApi _driveApi() {
    if (_api != null) return _api!;
    final enc = db.setting('drive_refresh_token');
    if (enc == null) throw DriveNotConnected();
    final refreshToken = box.decrypt(enc);
    final creds = auth.AccessCredentials(
      auth.AccessToken('Bearer', 'expired', DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
      refreshToken,
      driveScopes,
    );
    _client = auth.autoRefreshingClient(
      auth.ClientId(config.googleClientId, config.googleClientSecret),
      creds,
      _http,
    );
    return _api = drive.DriveApi(_client!);
  }

  void reset() {
    _client?.close();
    _client = null;
    _api = null;
  }

  Future<T> _call<T>(Future<T> Function(drive.DriveApi api) fn) async {
    final api = _driveApi();
    try {
      return await fn(api);
    } on auth.ServerRequestFailedException {
      reset();
      throw ApiError(503, 'Google Drive pristup je opozvan. Ponovo povežite nalog u Podešavanjima.',
          code: 'drive_not_connected');
    } on auth.AccessDeniedException {
      reset();
      throw ApiError(503, 'Google Drive pristup je opozvan. Ponovo povežite nalog u Podešavanjima.',
          code: 'drive_not_connected');
    }
  }

  Future<String> rootFolderId() async {
    final existing = db.setting('drive_root_folder_id');
    if (existing != null) {
      final ok = await _call((api) async {
        try {
          final f = await api.files.get(existing, $fields: 'id,trashed') as drive.File;
          return f.trashed != true;
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status == 404) return false;
          rethrow;
        }
      });
      if (ok) return existing;
    }
    final id = await _createFolder(_rootFolderName, null);
    db.setSetting('drive_root_folder_id', id);
    return id;
  }

  Future<String> _createFolder(String name, String? parent) => _call((api) async {
        final f = await api.files.create(
          drive.File()
            ..name = name
            ..mimeType = _folderMime
            ..parents = parent == null ? null : [parent]
            ..description = 'Napravila aplikacija Fotograf',
          $fields: 'id',
        );
        return f.id!;
      });

  /// Vraća folder projekta; pravi ga ako ne postoji ili je obrisan.
  Future<String> ensureProjectFolder(String projectId) async {
    final row = db.one('SELECT title, event_date, drive_folder_id FROM projects WHERE id = ?', [projectId]);
    if (row == null) throw ApiError.notFound('Projekat ne postoji.');
    final current = row['drive_folder_id'] as String?;
    if (current != null) {
      final alive = await _call((api) async {
        try {
          final f = await api.files.get(current, $fields: 'id,trashed') as drive.File;
          return f.trashed != true;
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status == 404) return false;
          rethrow;
        }
      });
      if (alive) return current;
    }
    final root = await rootFolderId();
    final id = await _createFolder(folderName(row['title'] as String, row['event_date'] as String?), root);
    db.exec('UPDATE projects SET drive_folder_id = ? WHERE id = ?', [id, projectId]);
    return id;
  }

  static String folderName(String title, String? date) {
    final clean = title.replaceAll(RegExp(r'[\\/\x00-\x1F]'), ' ').trim();
    return (date == null || date.isEmpty) ? clean : '$date · $clean';
  }

  Future<void> renameFolder(String folderId, String name) => _call((api) async {
        await api.files.update(drive.File()..name = name, folderId, $fields: 'id');
      });

  Future<String> upload({
    required String folderId,
    required String filename,
    required String mime,
    required Uint8List bytes,
  }) =>
      _call((api) async {
        final f = await api.files.create(
          drive.File()
            ..name = filename
            ..parents = [folderId]
            ..mimeType = mime,
          uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: mime),
          uploadOptions: drive.UploadOptions.resumable,
          $fields: 'id',
        );
        return f.id!;
      });

  Future<drive.Media> download(String fileId) => _call((api) async {
        return await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      });

  Future<Uint8List> downloadBytes(String fileId) async {
    final media = await download(fileId);
    final b = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  /// Premešta u Kantu na Drive-u (može se vratiti narednih 30 dana).
  Future<void> trash(String fileId) => _call((api) async {
        try {
          await api.files.update(drive.File()..trashed = true, fileId, $fields: 'id');
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status != 404) rethrow;
        }
      });

  Future<Map<String, Object?>> quota() => _call((api) async {
        final about = await api.about.get($fields: 'storageQuota,user(emailAddress)');
        final q = about.storageQuota;
        return {
          'limit': int.tryParse(q?.limit ?? ''),
          'usage': int.tryParse(q?.usage ?? ''),
          'email': about.user?.emailAddress,
        };
      });

  // ---------------------------------------------------------------------------
  // OAuth povezivanje (Authorization Code + PKCE)
  // ---------------------------------------------------------------------------

  Uri authorizationUrl({required String state, required String codeVerifier}) => Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        {
          'client_id': config.googleClientId,
          'redirect_uri': config.driveRedirectUri,
          'response_type': 'code',
          'scope': driveScopes.join(' '),
          'access_type': 'offline',
          'prompt': 'consent',
          'include_granted_scopes': 'false',
          'login_hint': config.driveEmail,
          'state': state,
          'code_challenge': pkceChallenge(codeVerifier),
          'code_challenge_method': 'S256',
        },
      );

  /// Razmenjuje kod za tokene i proverava da je Drive nalog baš administratorov.
  Future<String> completeAuthorization({
    required String code,
    required String codeVerifier,
    required GoogleIdTokenVerifier verifier,
  }) async {
    final res = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'code': code,
        'client_id': config.googleClientId,
        'client_secret': config.googleClientSecret,
        'redirect_uri': config.driveRedirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': codeVerifier,
      },
    );
    if (res.statusCode != 200) {
      throw ApiError(502, 'Google nije prihvatio povezivanje. Pokušajte ponovo.');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final refresh = body['refresh_token'] as String?;
    final idToken = body['id_token'] as String?;
    final scope = (body['scope'] as String? ?? '').split(' ');
    if (refresh == null || idToken == null) {
      throw ApiError(502, 'Google nije vratio trajni pristup. Pokušajte ponovo.');
    }
    if (!scope.contains('https://www.googleapis.com/auth/drive.file')) {
      await _revoke(refresh);
      throw ApiError.badRequest('Morate dozvoliti pristup Google Drive-u (štiklirajte polje na Google ekranu).');
    }
    final identity = await verifier.verify(idToken);
    if (!identity.emailVerified || identity.email != config.driveEmail) {
      await _revoke(refresh);
      throw ApiError.forbidden('Drive se može povezati samo sa nalogom ${config.driveEmail}.');
    }
    reset();
    db.setSetting('drive_refresh_token', box.encrypt(refresh));
    db.setSetting('drive_email', identity.email);
    return identity.email;
  }

  Future<void> disconnect() async {
    final enc = db.setting('drive_refresh_token');
    if (enc != null) {
      try {
        await _revoke(box.decrypt(enc));
      } catch (_) {}
    }
    reset();
    db.setSetting('drive_refresh_token', null);
    db.setSetting('drive_email', null);
  }

  Future<void> _revoke(String token) async {
    await _http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': token});
  }
}
