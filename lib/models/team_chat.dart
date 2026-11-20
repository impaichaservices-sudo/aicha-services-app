import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

/// Discussion interne de l'équipe (invisible des clients).
///   type 'shop'   : toute l'équipe d'une boutique (créée automatiquement)
///   type 'group'  : groupe créé par le Super Admin ou un responsable (réunion…)
///   type 'direct' : discussion privée entre deux membres
class TeamChat {
  final String id;
  final String type;
  final String shopId;
  final String name;
  final List<String> members;
  final Map<String, String> memberNames;
  final String lastMessage;
  final String lastSender;
  final DateTime? lastAt;
  final Map<String, DateTime> readBy;
  final String createdBy;
  final String activeRoom; // réunion en cours dans ce groupe
  final bool activeRoomVideo;

  const TeamChat({
    required this.id,
    required this.type,
    required this.shopId,
    required this.name,
    required this.members,
    required this.memberNames,
    required this.lastMessage,
    required this.lastSender,
    required this.lastAt,
    required this.readBy,
    required this.createdBy,
    this.activeRoom = '',
    this.activeRoomVideo = false,
  });

  bool get isDirect => type == 'direct';
  bool get isShop => type == 'shop';
  bool get isGroup => type == 'group';

  String otherUid(String me) =>
      members.firstWhere((m) => m != me, orElse: () => '');

  String titleFor(String me) {
    if (!isDirect) return name.isEmpty ? 'Groupe' : name;
    final o = otherUid(me);
    return memberNames[o] ?? 'Collègue';
  }

  bool unreadFor(String me) {
    if (lastAt == null || lastSender.isEmpty || lastSender == me) return false;
    final r = readBy[me];
    return r == null || r.isBefore(lastAt!);
  }

  factory TeamChat.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final names = <String, String>{};
    (m['memberNames'] as Map? ?? const {}).forEach((k, v) => names['$k'] = '$v');
    final read = <String, DateTime>{};
    (m['readBy'] as Map? ?? const {}).forEach((k, v) {
      final t = _date(v);
      if (t != null) read['$k'] = t;
    });
    return TeamChat(
      id: d.id,
      type: (m['type'] ?? 'group') as String,
      shopId: (m['shopId'] ?? 'main') as String,
      name: (m['name'] ?? '') as String,
      members: List<String>.from(m['members'] as List? ?? const []),
      memberNames: names,
      lastMessage: (m['lastMessage'] ?? '') as String,
      lastSender: (m['lastSender'] ?? '') as String,
      lastAt: _date(m['lastAt']) ??
          (d.metadata.hasPendingWrites ? DateTime.now() : null),
      readBy: read,
      createdBy: (m['createdBy'] ?? '') as String,
      activeRoom: (m['activeRoom'] ?? '') as String,
      activeRoomVideo: m['activeRoomVideo'] == true,
    );
  }
}

class TeamMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String type; // text | file | system
  final String fileUrl;
  final String fileName;
  final DateTime createdAt;
  final bool pending;

  const TeamMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.type,
    required this.fileUrl,
    required this.fileName,
    required this.createdAt,
    required this.pending,
  });

  factory TeamMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return TeamMessage(
      id: d.id,
      senderId: (m['senderId'] ?? '') as String,
      senderName: (m['senderName'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      type: (m['type'] ?? 'text') as String,
      fileUrl: (m['fileUrl'] ?? '') as String,
      fileName: (m['fileName'] ?? '') as String,
      createdAt: _date(m['createdAt']) ?? DateTime.now(),
      pending: d.metadata.hasPendingWrites,
    );
  }
}

/// Membre de l'équipe joignable (agent, responsable ou Super Admin).
class TeamPerson {
  final String uid;
  final String name;
  final String role; // Super Admin | Responsable | Agent
  final String shopId;
  const TeamPerson(this.uid, this.name, this.role, this.shopId);
}
