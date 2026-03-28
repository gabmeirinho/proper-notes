// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $NotesTableTable extends NotesTable
    with TableInfo<$NotesTableTable, NotesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
      'last_synced_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentHashMeta =
      const VerificationMeta('contentHash');
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
      'content_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseContentHashMeta =
      const VerificationMeta('baseContentHash');
  @override
  late final GeneratedColumn<String> baseContentHash = GeneratedColumn<String>(
      'base_content_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _remoteFileIdMeta =
      const VerificationMeta('remoteFileId');
  @override
  late final GeneratedColumn<String> remoteFileId = GeneratedColumn<String>(
      'remote_file_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        content,
        createdAt,
        updatedAt,
        deletedAt,
        lastSyncedAt,
        syncStatus,
        contentHash,
        baseContentHash,
        deviceId,
        remoteFileId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes_table';
  @override
  VerificationContext validateIntegrity(Insertable<NotesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    } else if (isInserting) {
      context.missing(_syncStatusMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
          _contentHashMeta,
          contentHash.isAcceptableOrUnknown(
              data['content_hash']!, _contentHashMeta));
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('base_content_hash')) {
      context.handle(
          _baseContentHashMeta,
          baseContentHash.isAcceptableOrUnknown(
              data['base_content_hash']!, _baseContentHashMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('remote_file_id')) {
      context.handle(
          _remoteFileIdMeta,
          remoteFileId.isAcceptableOrUnknown(
              data['remote_file_id']!, _remoteFileIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastSyncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_synced_at']),
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
      contentHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_hash'])!,
      baseContentHash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}base_content_hash']),
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      remoteFileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}remote_file_id']),
    );
  }

  @override
  $NotesTableTable createAlias(String alias) {
    return $NotesTableTable(attachedDatabase, alias);
  }
}

class NotesTableData extends DataClass implements Insertable<NotesTableData> {
  final String id;
  final String title;
  final String content;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int? lastSyncedAt;
  final String syncStatus;
  final String contentHash;
  final String? baseContentHash;
  final String deviceId;
  final String? remoteFileId;
  const NotesTableData(
      {required this.id,
      required this.title,
      required this.content,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      this.lastSyncedAt,
      required this.syncStatus,
      required this.contentHash,
      this.baseContentHash,
      required this.deviceId,
      this.remoteFileId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['content_hash'] = Variable<String>(contentHash);
    if (!nullToAbsent || baseContentHash != null) {
      map['base_content_hash'] = Variable<String>(baseContentHash);
    }
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || remoteFileId != null) {
      map['remote_file_id'] = Variable<String>(remoteFileId);
    }
    return map;
  }

  NotesTableCompanion toCompanion(bool nullToAbsent) {
    return NotesTableCompanion(
      id: Value(id),
      title: Value(title),
      content: Value(content),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      syncStatus: Value(syncStatus),
      contentHash: Value(contentHash),
      baseContentHash: baseContentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(baseContentHash),
      deviceId: Value(deviceId),
      remoteFileId: remoteFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteFileId),
    );
  }

  factory NotesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotesTableData(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<int?>(json['lastSyncedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      baseContentHash: serializer.fromJson<String?>(json['baseContentHash']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      remoteFileId: serializer.fromJson<String?>(json['remoteFileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastSyncedAt': serializer.toJson<int?>(lastSyncedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'contentHash': serializer.toJson<String>(contentHash),
      'baseContentHash': serializer.toJson<String?>(baseContentHash),
      'deviceId': serializer.toJson<String>(deviceId),
      'remoteFileId': serializer.toJson<String?>(remoteFileId),
    };
  }

  NotesTableData copyWith(
          {String? id,
          String? title,
          String? content,
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          Value<int?> lastSyncedAt = const Value.absent(),
          String? syncStatus,
          String? contentHash,
          Value<String?> baseContentHash = const Value.absent(),
          String? deviceId,
          Value<String?> remoteFileId = const Value.absent()}) =>
      NotesTableData(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastSyncedAt:
            lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        contentHash: contentHash ?? this.contentHash,
        baseContentHash: baseContentHash.present
            ? baseContentHash.value
            : this.baseContentHash,
        deviceId: deviceId ?? this.deviceId,
        remoteFileId:
            remoteFileId.present ? remoteFileId.value : this.remoteFileId,
      );
  NotesTableData copyWithCompanion(NotesTableCompanion data) {
    return NotesTableData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
      contentHash:
          data.contentHash.present ? data.contentHash.value : this.contentHash,
      baseContentHash: data.baseContentHash.present
          ? data.baseContentHash.value
          : this.baseContentHash,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      remoteFileId: data.remoteFileId.present
          ? data.remoteFileId.value
          : this.remoteFileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotesTableData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('contentHash: $contentHash, ')
          ..write('baseContentHash: $baseContentHash, ')
          ..write('deviceId: $deviceId, ')
          ..write('remoteFileId: $remoteFileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      content,
      createdAt,
      updatedAt,
      deletedAt,
      lastSyncedAt,
      syncStatus,
      contentHash,
      baseContentHash,
      deviceId,
      remoteFileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotesTableData &&
          other.id == this.id &&
          other.title == this.title &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.syncStatus == this.syncStatus &&
          other.contentHash == this.contentHash &&
          other.baseContentHash == this.baseContentHash &&
          other.deviceId == this.deviceId &&
          other.remoteFileId == this.remoteFileId);
}

class NotesTableCompanion extends UpdateCompanion<NotesTableData> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> content;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int?> lastSyncedAt;
  final Value<String> syncStatus;
  final Value<String> contentHash;
  final Value<String?> baseContentHash;
  final Value<String> deviceId;
  final Value<String?> remoteFileId;
  final Value<int> rowid;
  const NotesTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.baseContentHash = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.remoteFileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesTableCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    required String syncStatus,
    required String contentHash,
    this.baseContentHash = const Value.absent(),
    required String deviceId,
    this.remoteFileId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        syncStatus = Value(syncStatus),
        contentHash = Value(contentHash),
        deviceId = Value(deviceId);
  static Insertable<NotesTableData> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? content,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastSyncedAt,
    Expression<String>? syncStatus,
    Expression<String>? contentHash,
    Expression<String>? baseContentHash,
    Expression<String>? deviceId,
    Expression<String>? remoteFileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (contentHash != null) 'content_hash': contentHash,
      if (baseContentHash != null) 'base_content_hash': baseContentHash,
      if (deviceId != null) 'device_id': deviceId,
      if (remoteFileId != null) 'remote_file_id': remoteFileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? content,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int?>? lastSyncedAt,
      Value<String>? syncStatus,
      Value<String>? contentHash,
      Value<String?>? baseContentHash,
      Value<String>? deviceId,
      Value<String?>? remoteFileId,
      Value<int>? rowid}) {
    return NotesTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      contentHash: contentHash ?? this.contentHash,
      baseContentHash: baseContentHash ?? this.baseContentHash,
      deviceId: deviceId ?? this.deviceId,
      remoteFileId: remoteFileId ?? this.remoteFileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (baseContentHash.present) {
      map['base_content_hash'] = Variable<String>(baseContentHash.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (remoteFileId.present) {
      map['remote_file_id'] = Variable<String>(remoteFileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('contentHash: $contentHash, ')
          ..write('baseContentHash: $baseContentHash, ')
          ..write('deviceId: $deviceId, ')
          ..write('remoteFileId: $remoteFileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppMetadataTableTable extends AppMetadataTable
    with TableInfo<$AppMetadataTableTable, AppMetadataTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetadataTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<int> keyId = GeneratedColumn<int>(
      'key_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountEmailMeta =
      const VerificationMeta('accountEmail');
  @override
  late final GeneratedColumn<String> accountEmail = GeneratedColumn<String>(
      'account_email', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _driveSyncTokenMeta =
      const VerificationMeta('driveSyncToken');
  @override
  late final GeneratedColumn<String> driveSyncToken = GeneratedColumn<String>(
      'drive_sync_token', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastFullSyncAtMeta =
      const VerificationMeta('lastFullSyncAt');
  @override
  late final GeneratedColumn<int> lastFullSyncAt = GeneratedColumn<int>(
      'last_full_sync_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastSuccessfulSyncAtMeta =
      const VerificationMeta('lastSuccessfulSyncAt');
  @override
  late final GeneratedColumn<int> lastSuccessfulSyncAt = GeneratedColumn<int>(
      'last_successful_sync_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        keyId,
        deviceId,
        accountEmail,
        driveSyncToken,
        lastFullSyncAt,
        lastSuccessfulSyncAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_metadata_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<AppMetadataTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_id')) {
      context.handle(
          _keyIdMeta, keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('account_email')) {
      context.handle(
          _accountEmailMeta,
          accountEmail.isAcceptableOrUnknown(
              data['account_email']!, _accountEmailMeta));
    }
    if (data.containsKey('drive_sync_token')) {
      context.handle(
          _driveSyncTokenMeta,
          driveSyncToken.isAcceptableOrUnknown(
              data['drive_sync_token']!, _driveSyncTokenMeta));
    }
    if (data.containsKey('last_full_sync_at')) {
      context.handle(
          _lastFullSyncAtMeta,
          lastFullSyncAt.isAcceptableOrUnknown(
              data['last_full_sync_at']!, _lastFullSyncAtMeta));
    }
    if (data.containsKey('last_successful_sync_at')) {
      context.handle(
          _lastSuccessfulSyncAtMeta,
          lastSuccessfulSyncAt.isAcceptableOrUnknown(
              data['last_successful_sync_at']!, _lastSuccessfulSyncAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyId};
  @override
  AppMetadataTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetadataTableData(
      keyId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}key_id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      accountEmail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_email']),
      driveSyncToken: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}drive_sync_token']),
      lastFullSyncAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_full_sync_at']),
      lastSuccessfulSyncAt: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_successful_sync_at']),
    );
  }

  @override
  $AppMetadataTableTable createAlias(String alias) {
    return $AppMetadataTableTable(attachedDatabase, alias);
  }
}

class AppMetadataTableData extends DataClass
    implements Insertable<AppMetadataTableData> {
  final int keyId;
  final String deviceId;
  final String? accountEmail;
  final String? driveSyncToken;
  final int? lastFullSyncAt;
  final int? lastSuccessfulSyncAt;
  const AppMetadataTableData(
      {required this.keyId,
      required this.deviceId,
      this.accountEmail,
      this.driveSyncToken,
      this.lastFullSyncAt,
      this.lastSuccessfulSyncAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_id'] = Variable<int>(keyId);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || accountEmail != null) {
      map['account_email'] = Variable<String>(accountEmail);
    }
    if (!nullToAbsent || driveSyncToken != null) {
      map['drive_sync_token'] = Variable<String>(driveSyncToken);
    }
    if (!nullToAbsent || lastFullSyncAt != null) {
      map['last_full_sync_at'] = Variable<int>(lastFullSyncAt);
    }
    if (!nullToAbsent || lastSuccessfulSyncAt != null) {
      map['last_successful_sync_at'] = Variable<int>(lastSuccessfulSyncAt);
    }
    return map;
  }

  AppMetadataTableCompanion toCompanion(bool nullToAbsent) {
    return AppMetadataTableCompanion(
      keyId: Value(keyId),
      deviceId: Value(deviceId),
      accountEmail: accountEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(accountEmail),
      driveSyncToken: driveSyncToken == null && nullToAbsent
          ? const Value.absent()
          : Value(driveSyncToken),
      lastFullSyncAt: lastFullSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFullSyncAt),
      lastSuccessfulSyncAt: lastSuccessfulSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessfulSyncAt),
    );
  }

  factory AppMetadataTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetadataTableData(
      keyId: serializer.fromJson<int>(json['keyId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      accountEmail: serializer.fromJson<String?>(json['accountEmail']),
      driveSyncToken: serializer.fromJson<String?>(json['driveSyncToken']),
      lastFullSyncAt: serializer.fromJson<int?>(json['lastFullSyncAt']),
      lastSuccessfulSyncAt:
          serializer.fromJson<int?>(json['lastSuccessfulSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyId': serializer.toJson<int>(keyId),
      'deviceId': serializer.toJson<String>(deviceId),
      'accountEmail': serializer.toJson<String?>(accountEmail),
      'driveSyncToken': serializer.toJson<String?>(driveSyncToken),
      'lastFullSyncAt': serializer.toJson<int?>(lastFullSyncAt),
      'lastSuccessfulSyncAt': serializer.toJson<int?>(lastSuccessfulSyncAt),
    };
  }

  AppMetadataTableData copyWith(
          {int? keyId,
          String? deviceId,
          Value<String?> accountEmail = const Value.absent(),
          Value<String?> driveSyncToken = const Value.absent(),
          Value<int?> lastFullSyncAt = const Value.absent(),
          Value<int?> lastSuccessfulSyncAt = const Value.absent()}) =>
      AppMetadataTableData(
        keyId: keyId ?? this.keyId,
        deviceId: deviceId ?? this.deviceId,
        accountEmail:
            accountEmail.present ? accountEmail.value : this.accountEmail,
        driveSyncToken:
            driveSyncToken.present ? driveSyncToken.value : this.driveSyncToken,
        lastFullSyncAt:
            lastFullSyncAt.present ? lastFullSyncAt.value : this.lastFullSyncAt,
        lastSuccessfulSyncAt: lastSuccessfulSyncAt.present
            ? lastSuccessfulSyncAt.value
            : this.lastSuccessfulSyncAt,
      );
  AppMetadataTableData copyWithCompanion(AppMetadataTableCompanion data) {
    return AppMetadataTableData(
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      accountEmail: data.accountEmail.present
          ? data.accountEmail.value
          : this.accountEmail,
      driveSyncToken: data.driveSyncToken.present
          ? data.driveSyncToken.value
          : this.driveSyncToken,
      lastFullSyncAt: data.lastFullSyncAt.present
          ? data.lastFullSyncAt.value
          : this.lastFullSyncAt,
      lastSuccessfulSyncAt: data.lastSuccessfulSyncAt.present
          ? data.lastSuccessfulSyncAt.value
          : this.lastSuccessfulSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetadataTableData(')
          ..write('keyId: $keyId, ')
          ..write('deviceId: $deviceId, ')
          ..write('accountEmail: $accountEmail, ')
          ..write('driveSyncToken: $driveSyncToken, ')
          ..write('lastFullSyncAt: $lastFullSyncAt, ')
          ..write('lastSuccessfulSyncAt: $lastSuccessfulSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyId, deviceId, accountEmail, driveSyncToken,
      lastFullSyncAt, lastSuccessfulSyncAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetadataTableData &&
          other.keyId == this.keyId &&
          other.deviceId == this.deviceId &&
          other.accountEmail == this.accountEmail &&
          other.driveSyncToken == this.driveSyncToken &&
          other.lastFullSyncAt == this.lastFullSyncAt &&
          other.lastSuccessfulSyncAt == this.lastSuccessfulSyncAt);
}

class AppMetadataTableCompanion extends UpdateCompanion<AppMetadataTableData> {
  final Value<int> keyId;
  final Value<String> deviceId;
  final Value<String?> accountEmail;
  final Value<String?> driveSyncToken;
  final Value<int?> lastFullSyncAt;
  final Value<int?> lastSuccessfulSyncAt;
  const AppMetadataTableCompanion({
    this.keyId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.accountEmail = const Value.absent(),
    this.driveSyncToken = const Value.absent(),
    this.lastFullSyncAt = const Value.absent(),
    this.lastSuccessfulSyncAt = const Value.absent(),
  });
  AppMetadataTableCompanion.insert({
    this.keyId = const Value.absent(),
    required String deviceId,
    this.accountEmail = const Value.absent(),
    this.driveSyncToken = const Value.absent(),
    this.lastFullSyncAt = const Value.absent(),
    this.lastSuccessfulSyncAt = const Value.absent(),
  }) : deviceId = Value(deviceId);
  static Insertable<AppMetadataTableData> custom({
    Expression<int>? keyId,
    Expression<String>? deviceId,
    Expression<String>? accountEmail,
    Expression<String>? driveSyncToken,
    Expression<int>? lastFullSyncAt,
    Expression<int>? lastSuccessfulSyncAt,
  }) {
    return RawValuesInsertable({
      if (keyId != null) 'key_id': keyId,
      if (deviceId != null) 'device_id': deviceId,
      if (accountEmail != null) 'account_email': accountEmail,
      if (driveSyncToken != null) 'drive_sync_token': driveSyncToken,
      if (lastFullSyncAt != null) 'last_full_sync_at': lastFullSyncAt,
      if (lastSuccessfulSyncAt != null)
        'last_successful_sync_at': lastSuccessfulSyncAt,
    });
  }

  AppMetadataTableCompanion copyWith(
      {Value<int>? keyId,
      Value<String>? deviceId,
      Value<String?>? accountEmail,
      Value<String?>? driveSyncToken,
      Value<int?>? lastFullSyncAt,
      Value<int?>? lastSuccessfulSyncAt}) {
    return AppMetadataTableCompanion(
      keyId: keyId ?? this.keyId,
      deviceId: deviceId ?? this.deviceId,
      accountEmail: accountEmail ?? this.accountEmail,
      driveSyncToken: driveSyncToken ?? this.driveSyncToken,
      lastFullSyncAt: lastFullSyncAt ?? this.lastFullSyncAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyId.present) {
      map['key_id'] = Variable<int>(keyId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (accountEmail.present) {
      map['account_email'] = Variable<String>(accountEmail.value);
    }
    if (driveSyncToken.present) {
      map['drive_sync_token'] = Variable<String>(driveSyncToken.value);
    }
    if (lastFullSyncAt.present) {
      map['last_full_sync_at'] = Variable<int>(lastFullSyncAt.value);
    }
    if (lastSuccessfulSyncAt.present) {
      map['last_successful_sync_at'] =
          Variable<int>(lastSuccessfulSyncAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetadataTableCompanion(')
          ..write('keyId: $keyId, ')
          ..write('deviceId: $deviceId, ')
          ..write('accountEmail: $accountEmail, ')
          ..write('driveSyncToken: $driveSyncToken, ')
          ..write('lastFullSyncAt: $lastFullSyncAt, ')
          ..write('lastSuccessfulSyncAt: $lastSuccessfulSyncAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NotesTableTable notesTable = $NotesTableTable(this);
  late final $AppMetadataTableTable appMetadataTable =
      $AppMetadataTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [notesTable, appMetadataTable];
}

typedef $$NotesTableTableCreateCompanionBuilder = NotesTableCompanion Function({
  required String id,
  Value<String> title,
  Value<String> content,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  Value<int?> lastSyncedAt,
  required String syncStatus,
  required String contentHash,
  Value<String?> baseContentHash,
  required String deviceId,
  Value<String?> remoteFileId,
  Value<int> rowid,
});
typedef $$NotesTableTableUpdateCompanionBuilder = NotesTableCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> content,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int?> lastSyncedAt,
  Value<String> syncStatus,
  Value<String> contentHash,
  Value<String?> baseContentHash,
  Value<String> deviceId,
  Value<String?> remoteFileId,
  Value<int> rowid,
});

class $$NotesTableTableFilterComposer
    extends Composer<_$AppDatabase, $NotesTableTable> {
  $$NotesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseContentHash => $composableBuilder(
      column: $table.baseContentHash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remoteFileId => $composableBuilder(
      column: $table.remoteFileId, builder: (column) => ColumnFilters(column));
}

class $$NotesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTableTable> {
  $$NotesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseContentHash => $composableBuilder(
      column: $table.baseContentHash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remoteFileId => $composableBuilder(
      column: $table.remoteFileId,
      builder: (column) => ColumnOrderings(column));
}

class $$NotesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTableTable> {
  $$NotesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => column);

  GeneratedColumn<String> get baseContentHash => $composableBuilder(
      column: $table.baseContentHash, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get remoteFileId => $composableBuilder(
      column: $table.remoteFileId, builder: (column) => column);
}

class $$NotesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $NotesTableTable,
    NotesTableData,
    $$NotesTableTableFilterComposer,
    $$NotesTableTableOrderingComposer,
    $$NotesTableTableAnnotationComposer,
    $$NotesTableTableCreateCompanionBuilder,
    $$NotesTableTableUpdateCompanionBuilder,
    (
      NotesTableData,
      BaseReferences<_$AppDatabase, $NotesTableTable, NotesTableData>
    ),
    NotesTableData,
    PrefetchHooks Function()> {
  $$NotesTableTableTableManager(_$AppDatabase db, $NotesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<String> contentHash = const Value.absent(),
            Value<String?> baseContentHash = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String?> remoteFileId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NotesTableCompanion(
            id: id,
            title: title,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastSyncedAt: lastSyncedAt,
            syncStatus: syncStatus,
            contentHash: contentHash,
            baseContentHash: baseContentHash,
            deviceId: deviceId,
            remoteFileId: remoteFileId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> title = const Value.absent(),
            Value<String> content = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            Value<int?> lastSyncedAt = const Value.absent(),
            required String syncStatus,
            required String contentHash,
            Value<String?> baseContentHash = const Value.absent(),
            required String deviceId,
            Value<String?> remoteFileId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NotesTableCompanion.insert(
            id: id,
            title: title,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastSyncedAt: lastSyncedAt,
            syncStatus: syncStatus,
            contentHash: contentHash,
            baseContentHash: baseContentHash,
            deviceId: deviceId,
            remoteFileId: remoteFileId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$NotesTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $NotesTableTable,
    NotesTableData,
    $$NotesTableTableFilterComposer,
    $$NotesTableTableOrderingComposer,
    $$NotesTableTableAnnotationComposer,
    $$NotesTableTableCreateCompanionBuilder,
    $$NotesTableTableUpdateCompanionBuilder,
    (
      NotesTableData,
      BaseReferences<_$AppDatabase, $NotesTableTable, NotesTableData>
    ),
    NotesTableData,
    PrefetchHooks Function()>;
typedef $$AppMetadataTableTableCreateCompanionBuilder
    = AppMetadataTableCompanion Function({
  Value<int> keyId,
  required String deviceId,
  Value<String?> accountEmail,
  Value<String?> driveSyncToken,
  Value<int?> lastFullSyncAt,
  Value<int?> lastSuccessfulSyncAt,
});
typedef $$AppMetadataTableTableUpdateCompanionBuilder
    = AppMetadataTableCompanion Function({
  Value<int> keyId,
  Value<String> deviceId,
  Value<String?> accountEmail,
  Value<String?> driveSyncToken,
  Value<int?> lastFullSyncAt,
  Value<int?> lastSuccessfulSyncAt,
});

class $$AppMetadataTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppMetadataTableTable> {
  $$AppMetadataTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get keyId => $composableBuilder(
      column: $table.keyId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountEmail => $composableBuilder(
      column: $table.accountEmail, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driveSyncToken => $composableBuilder(
      column: $table.driveSyncToken,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastFullSyncAt => $composableBuilder(
      column: $table.lastFullSyncAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSuccessfulSyncAt => $composableBuilder(
      column: $table.lastSuccessfulSyncAt,
      builder: (column) => ColumnFilters(column));
}

class $$AppMetadataTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppMetadataTableTable> {
  $$AppMetadataTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get keyId => $composableBuilder(
      column: $table.keyId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountEmail => $composableBuilder(
      column: $table.accountEmail,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driveSyncToken => $composableBuilder(
      column: $table.driveSyncToken,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastFullSyncAt => $composableBuilder(
      column: $table.lastFullSyncAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSuccessfulSyncAt => $composableBuilder(
      column: $table.lastSuccessfulSyncAt,
      builder: (column) => ColumnOrderings(column));
}

class $$AppMetadataTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppMetadataTableTable> {
  $$AppMetadataTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get accountEmail => $composableBuilder(
      column: $table.accountEmail, builder: (column) => column);

  GeneratedColumn<String> get driveSyncToken => $composableBuilder(
      column: $table.driveSyncToken, builder: (column) => column);

  GeneratedColumn<int> get lastFullSyncAt => $composableBuilder(
      column: $table.lastFullSyncAt, builder: (column) => column);

  GeneratedColumn<int> get lastSuccessfulSyncAt => $composableBuilder(
      column: $table.lastSuccessfulSyncAt, builder: (column) => column);
}

class $$AppMetadataTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppMetadataTableTable,
    AppMetadataTableData,
    $$AppMetadataTableTableFilterComposer,
    $$AppMetadataTableTableOrderingComposer,
    $$AppMetadataTableTableAnnotationComposer,
    $$AppMetadataTableTableCreateCompanionBuilder,
    $$AppMetadataTableTableUpdateCompanionBuilder,
    (
      AppMetadataTableData,
      BaseReferences<_$AppDatabase, $AppMetadataTableTable,
          AppMetadataTableData>
    ),
    AppMetadataTableData,
    PrefetchHooks Function()> {
  $$AppMetadataTableTableTableManager(
      _$AppDatabase db, $AppMetadataTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppMetadataTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppMetadataTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppMetadataTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> keyId = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String?> accountEmail = const Value.absent(),
            Value<String?> driveSyncToken = const Value.absent(),
            Value<int?> lastFullSyncAt = const Value.absent(),
            Value<int?> lastSuccessfulSyncAt = const Value.absent(),
          }) =>
              AppMetadataTableCompanion(
            keyId: keyId,
            deviceId: deviceId,
            accountEmail: accountEmail,
            driveSyncToken: driveSyncToken,
            lastFullSyncAt: lastFullSyncAt,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
          ),
          createCompanionCallback: ({
            Value<int> keyId = const Value.absent(),
            required String deviceId,
            Value<String?> accountEmail = const Value.absent(),
            Value<String?> driveSyncToken = const Value.absent(),
            Value<int?> lastFullSyncAt = const Value.absent(),
            Value<int?> lastSuccessfulSyncAt = const Value.absent(),
          }) =>
              AppMetadataTableCompanion.insert(
            keyId: keyId,
            deviceId: deviceId,
            accountEmail: accountEmail,
            driveSyncToken: driveSyncToken,
            lastFullSyncAt: lastFullSyncAt,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppMetadataTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppMetadataTableTable,
    AppMetadataTableData,
    $$AppMetadataTableTableFilterComposer,
    $$AppMetadataTableTableOrderingComposer,
    $$AppMetadataTableTableAnnotationComposer,
    $$AppMetadataTableTableCreateCompanionBuilder,
    $$AppMetadataTableTableUpdateCompanionBuilder,
    (
      AppMetadataTableData,
      BaseReferences<_$AppDatabase, $AppMetadataTableTable,
          AppMetadataTableData>
    ),
    AppMetadataTableData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NotesTableTableTableManager get notesTable =>
      $$NotesTableTableTableManager(_db, _db.notesTable);
  $$AppMetadataTableTableTableManager get appMetadataTable =>
      $$AppMetadataTableTableTableManager(_db, _db.appMetadataTable);
}
