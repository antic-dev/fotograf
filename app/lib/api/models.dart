List<String> _strings(Object? v) => (v as List? ?? const []).cast<String>();

class Photo {
  Photo({required this.id, required this.name, required this.w, required this.h, this.selectedBy = 0, this.takenAt});

  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        w: j['w'] as int? ?? 1,
        h: j['h'] as int? ?? 1,
        selectedBy: j['selectedBy'] as int? ?? 0,
        takenAt: j['takenAt'] as int?,
      );

  final String id;
  final String name;
  final int w;
  final int h;
  final int selectedBy;
  final int? takenAt;

  double get aspect => h == 0 ? 1 : w / h;
}

class OrderItem {
  OrderItem({required this.photoId, required this.quantity, required this.size, required this.finish});

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        photoId: j['photoId'] as String,
        quantity: j['quantity'] as int,
        size: j['size'] as String,
        finish: j['finish'] as String,
      );

  final String photoId;
  final int quantity;
  final String size;
  final String finish;

  OrderItem copyWith({int? quantity, String? size, String? finish}) => OrderItem(
        photoId: photoId,
        quantity: quantity ?? this.quantity,
        size: size ?? this.size,
        finish: finish ?? this.finish,
      );
}

/// Izbor klijenta u jednom projektu.
class ClientOrder {
  ClientOrder({required this.status, required this.name, required this.phone, required this.note, required this.items, this.submittedAt});

  factory ClientOrder.fromJson(Map<String, dynamic> j) => ClientOrder(
        status: j['status'] as String? ?? 'draft',
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        note: j['note'] as String? ?? '',
        submittedAt: j['submittedAt'] as int?,
        items: [for (final i in (j['items'] as List? ?? const [])) OrderItem.fromJson(i as Map<String, dynamic>)],
      );

  final String status;
  final String name;
  final String phone;
  final String note;
  final int? submittedAt;
  final List<OrderItem> items;

  bool get isDraft => status == 'draft';
}

class ClientProject {
  ClientProject({
    required this.title,
    required this.clientName,
    required this.eventDate,
    required this.message,
    required this.status,
    required this.canSelect,
    required this.maxPhotos,
    required this.deadline,
    required this.sizes,
    required this.finishes,
    required this.coverPhotoId,
  });

  factory ClientProject.fromJson(Map<String, dynamic> j) => ClientProject(
        title: j['title'] as String,
        clientName: j['clientName'] as String? ?? '',
        eventDate: j['eventDate'] as String?,
        message: j['message'] as String? ?? '',
        status: j['status'] as String,
        canSelect: j['canSelect'] as bool? ?? false,
        maxPhotos: j['maxPhotos'] as int?,
        deadline: j['deadline'] as int?,
        sizes: _strings(j['sizes']),
        finishes: _strings(j['finishes']),
        coverPhotoId: j['coverPhotoId'] as String?,
      );

  final String title;
  final String clientName;
  final String? eventDate;
  final String message;
  final String status;
  final bool canSelect;
  final int? maxPhotos;
  final int? deadline;
  final List<String> sizes;
  final List<String> finishes;
  final String? coverPhotoId;
}

class Project {
  Project({
    required this.id,
    required this.title,
    required this.clientName,
    required this.eventDate,
    required this.message,
    required this.status,
    required this.maxPhotos,
    required this.deadline,
    required this.watermark,
    required this.sizes,
    required this.finishes,
    required this.coverPhotoId,
    required this.driveFolderUrl,
    required this.shareUrl,
    required this.photoCount,
    required this.newOrders,
    required this.totalOrders,
    required this.activeDrafts,
    required this.createdAt,
    this.photos = const [],
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        title: j['title'] as String,
        clientName: j['clientName'] as String? ?? '',
        eventDate: j['eventDate'] as String?,
        message: j['message'] as String? ?? '',
        status: j['status'] as String,
        maxPhotos: j['maxPhotos'] as int?,
        deadline: j['deadline'] as int?,
        watermark: j['watermark'] as bool? ?? true,
        sizes: _strings(j['sizes']),
        finishes: _strings(j['finishes']),
        coverPhotoId: j['coverPhotoId'] as String?,
        driveFolderUrl: j['driveFolderUrl'] as String?,
        shareUrl: j['shareUrl'] as String,
        photoCount: j['photoCount'] as int? ?? 0,
        newOrders: j['newOrders'] as int? ?? 0,
        totalOrders: j['totalOrders'] as int? ?? 0,
        activeDrafts: j['activeDrafts'] as int? ?? 0,
        createdAt: j['createdAt'] as int? ?? 0,
        photos: [for (final p in (j['photos'] as List? ?? const [])) Photo.fromJson(p as Map<String, dynamic>)],
      );

  final String id;
  final String title;
  final String clientName;
  final String? eventDate;
  final String message;
  final String status;
  final int? maxPhotos;
  final int? deadline;
  final bool watermark;
  final List<String> sizes;
  final List<String> finishes;
  final String? coverPhotoId;
  final String? driveFolderUrl;
  final String shareUrl;
  final int photoCount;
  final int newOrders;
  final int totalOrders;
  final int activeDrafts;
  final int createdAt;
  final List<Photo> photos;
}

class AdminOrderItem {
  AdminOrderItem({required this.photoId, required this.filename, required this.quantity, required this.size, required this.finish, required this.w, required this.h});

  factory AdminOrderItem.fromJson(Map<String, dynamic> j) => AdminOrderItem(
        photoId: j['photoId'] as String,
        filename: j['filename'] as String,
        quantity: j['quantity'] as int,
        size: j['size'] as String,
        finish: j['finish'] as String,
        w: j['w'] as int? ?? 1,
        h: j['h'] as int? ?? 1,
      );

  final String photoId;
  final String filename;
  final int quantity;
  final String size;
  final String finish;
  final int w;
  final int h;
}

class AdminOrder {
  AdminOrder({
    required this.id,
    required this.projectId,
    required this.projectTitle,
    required this.status,
    required this.name,
    required this.phone,
    required this.note,
    required this.submittedAt,
    required this.updatedAt,
    required this.photoCount,
    required this.copies,
    required this.previewPhotoIds,
    this.items = const [],
  });

  factory AdminOrder.fromJson(Map<String, dynamic> j) => AdminOrder(
        id: j['id'] as String,
        projectId: j['projectId'] as String,
        projectTitle: j['projectTitle'] as String? ?? '',
        status: j['status'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        note: j['note'] as String? ?? '',
        submittedAt: j['submittedAt'] as int?,
        updatedAt: j['updatedAt'] as int? ?? 0,
        photoCount: j['photoCount'] as int? ?? 0,
        copies: j['copies'] as int? ?? 0,
        previewPhotoIds: _strings(j['previewPhotoIds']),
        items: [for (final i in (j['items'] as List? ?? const [])) AdminOrderItem.fromJson(i as Map<String, dynamic>)],
      );

  final String id;
  final String projectId;
  final String projectTitle;
  final String status;
  final String name;
  final String phone;
  final String note;
  final int? submittedAt;
  final int updatedAt;
  final int photoCount;
  final int copies;
  final List<String> previewPhotoIds;
  final List<AdminOrderItem> items;

  String get displayName => name.isEmpty ? 'Klijent (bez imena)' : name;
}

class PrintLink {
  PrintLink({
    required this.id,
    required this.label,
    required this.url,
    required this.createdAt,
    required this.expiresAt,
    required this.revoked,
    required this.expired,
    required this.accessCount,
    required this.sentTo,
    required this.photoCount,
    required this.copies,
    required this.mailTo,
    required this.mailSubject,
    required this.mailBody,
  });

  factory PrintLink.fromJson(Map<String, dynamic> j) {
    final mail = j['mail'] as Map<String, dynamic>? ?? const {};
    return PrintLink(
      id: j['id'] as String,
      label: j['label'] as String,
      url: j['url'] as String,
      createdAt: j['createdAt'] as int,
      expiresAt: j['expiresAt'] as int,
      revoked: j['revoked'] as bool? ?? false,
      expired: j['expired'] as bool? ?? false,
      accessCount: j['accessCount'] as int? ?? 0,
      sentTo: j['sentTo'] as String? ?? '',
      photoCount: j['photoCount'] as int? ?? 0,
      copies: j['copies'] as int? ?? 0,
      mailTo: mail['to'] as String? ?? '',
      mailSubject: mail['subject'] as String? ?? '',
      mailBody: mail['body'] as String? ?? '',
    );
  }

  final String id;
  final String label;
  final String url;
  final int createdAt;
  final int expiresAt;
  final bool revoked;
  final bool expired;
  final int accessCount;
  final String sentTo;
  final int photoCount;
  final int copies;
  final String mailTo;
  final String mailSubject;
  final String mailBody;

  bool get active => !revoked && !expired;
}

class Settings {
  Settings({
    required this.studioName,
    required this.watermarkText,
    required this.printerEmail,
    required this.defaultSizes,
    required this.defaultFinishes,
    required this.smtpEnabled,
    required this.adminEmail,
    required this.driveConnected,
    required this.driveEmail,
    required this.activeSessions,
  });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        studioName: j['studioName'] as String,
        watermarkText: j['watermarkText'] as String? ?? '',
        printerEmail: j['printerEmail'] as String? ?? '',
        defaultSizes: _strings(j['defaultSizes']),
        defaultFinishes: _strings(j['defaultFinishes']),
        smtpEnabled: j['smtpEnabled'] as bool? ?? false,
        adminEmail: j['adminEmail'] as String? ?? '',
        driveConnected: (j['drive'] as Map?)?['connected'] as bool? ?? false,
        driveEmail: (j['drive'] as Map?)?['email'] as String?,
        activeSessions: j['activeSessions'] as int? ?? 0,
      );

  final String studioName;
  final String watermarkText;
  final String printerEmail;
  final List<String> defaultSizes;
  final List<String> defaultFinishes;
  final bool smtpEnabled;
  final String adminEmail;
  final bool driveConnected;
  final String? driveEmail;
  final int activeSessions;
}
