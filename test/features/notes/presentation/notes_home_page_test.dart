import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proper_notes/features/auth/application/auth_controller.dart';
import 'package:proper_notes/features/auth/domain/auth_service.dart';
import 'package:proper_notes/features/auth/domain/auth_session.dart';
import 'package:proper_notes/features/notes/application/create_folder.dart';
import 'package:proper_notes/features/notes/application/create_note.dart';
import 'package:proper_notes/features/notes/application/delete_folder.dart';
import 'package:proper_notes/features/notes/application/delete_note.dart';
import 'package:proper_notes/features/notes/application/move_note.dart';
import 'package:proper_notes/features/notes/application/rename_folder.dart';
import 'package:proper_notes/features/notes/application/restore_note.dart';
import 'package:proper_notes/features/notes/application/search_notes.dart';
import 'package:proper_notes/features/notes/application/update_note.dart';
import 'package:proper_notes/features/notes/domain/folder.dart';
import 'package:proper_notes/features/notes/domain/folder_repository.dart';
import 'package:proper_notes/features/notes/domain/note.dart';
import 'package:proper_notes/features/notes/domain/note_repository.dart';
import 'package:proper_notes/features/notes/domain/sync_status.dart';
import 'package:proper_notes/features/notes/presentation/notes_home_page.dart';
import 'package:proper_notes/features/sync/application/run_manual_sync.dart';
import 'package:proper_notes/features/sync/application/sync_controller.dart';
import 'package:proper_notes/features/sync/domain/remote_note.dart';
import 'package:proper_notes/features/sync/domain/sync_gateway.dart';
import 'package:proper_notes/features/sync/domain/sync_state_repository.dart';

void main() {
  testWidgets(
    'wide layout shows a stable desktop workspace shell before opening a note',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final noteRepository = _FakeNoteRepository();
      final folderRepository = _FakeFolderRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('desktop-workspace')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-editor-placeholder')),
        findsOneWidget,
      );
      expect(find.text('Workspace'), findsOneWidget);
      expect(
        find.text('Keep writing without leaving the workspace.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'mobile layout removes banner boxes and shows folder path in the app bar',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final noteRepository = _FakeNoteRepository();
      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Shortcuts:'), findsNothing);
      expect(find.text('Sync ready'), findsNothing);
      expect(find.text('No sync has completed yet'), findsNothing);
      expect(find.text('Folder: Projects'), findsNothing);

      await tester.tap(find.byTooltip('Folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mobile-folder-path-title')),
          findsOneWidget);
      expect(find.text('Projects'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Shortcuts:'), findsNothing);
      expect(find.text('Sync ready'), findsNothing);
      expect(find.text('Folder: Projects'), findsNothing);
    },
  );

  testWidgets(
    'wide layout keeps the folder sidebar visible when opening the editor',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final noteRepository = _FakeNoteRepository();
      final folderRepository = _FakeFolderRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Workspace'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-editor-placeholder')),
        findsOneWidget,
      );
      expect(find.byTooltip('Close editor'), findsNothing);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'New note'));
      await tester.pumpAndSettle();

      expect(find.text('Workspace'), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-workspace')), findsOneWidget);
      expect(
          find.widgetWithText(FloatingActionButton, 'New note'), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-editor-placeholder')),
        findsNothing,
      );
      expect(find.byTooltip('Close editor'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    },
  );

  testWidgets(
    'desktop sidebar folder click toggles note visibility',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        deleteImpact: const FolderDeleteImpact(
          noteCount: 1,
          childFolderCount: 0,
        ),
      );
      final noteRepository = _FakeNoteRepository(
        initialActiveNotes: [
          Note(
            id: 'note-1',
            title: 'Roadmap',
            content: 'Plan the next release',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 2),
            syncStatus: SyncStatus.synced,
            contentHash: 'hash-1',
            deviceId: 'device-1',
            folderPath: 'Projects',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Roadmap'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('sidebar-folder-tile-Projects')),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('sidebar-note-note-1')), findsOneWidget);
      expect(find.text('Roadmap'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('sidebar-folder-tile-Projects')),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('sidebar-note-note-1')), findsNothing);
      expect(find.text('Roadmap'), findsNothing);
    },
  );

  testWidgets(
    'desktop folder menu offers new note and opens the editor in that folder',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        deleteImpact: const FolderDeleteImpact(
          noteCount: 1,
          childFolderCount: 0,
        ),
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();

      expect(find.text('New note'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('New note').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Folder: Projects'), findsNothing);
    },
  );

  testWidgets(
    'desktop folder menu offers creating a new folder and standalone new-folder icons are removed',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip('New folder'), findsNothing);

      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();

      expect(find.text('New folder'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'sidebar note row shows sync status indicator',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final noteRepository = _FakeNoteRepository(
        initialActiveNotes: [
          Note(
            id: 'note-1',
            title: 'Roadmap',
            content: 'Plan the next release',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 2),
            syncStatus: SyncStatus.pendingUpload,
            contentHash: 'hash-1',
            deviceId: 'device-1',
            folderPath: 'Projects',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(
        find.byKey(const ValueKey('sidebar-folder-tile-Projects')),
      );
      await tester.pump();

      expect(find.byTooltip('Pending sync'), findsOneWidget);
    },
  );

  testWidgets(
    'note actions menu offers move and updates the note folder',
    (tester) async {
      final folderRepository = _FakeFolderRepository();
      final noteRepository = _FakeNoteRepository(
        initialActiveNotes: [
          Note(
            id: 'note-1',
            title: 'Roadmap',
            content: 'Plan the next release',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 2),
            syncStatus: SyncStatus.synced,
            contentHash: 'hash-1',
            deviceId: 'device-1',
            folderPath: 'Projects',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Note actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, 'Archive');
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();

      expect(noteRepository.updatedNotes, hasLength(1));
      expect(noteRepository.updatedNotes.single.folderPath, 'Archive');
    },
  );

  testWidgets(
    'folder menu offers rename and updates folder path state',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, 'Archive');
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();

      expect(folderRepository.renamedPaths, [('Projects', 'Archive')]);
    },
  );

  testWidgets(
    'folder menu offers move',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
          Folder(
            path: 'Archive',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester
          .tap(find.byKey(const ValueKey('sidebar-folder-tile-Projects')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sidebar-folder-tile-Projects')),
          matching: find.byTooltip('Folder actions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move').last);
      await tester.pumpAndSettle();

      expect(find.text('Move folder'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    },
  );

  testWidgets(
    'desktop sidebar supports dragging a note into a folder',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final noteRepository = _FakeNoteRepository(
        initialActiveNotes: [
          Note(
            id: 'note-1',
            title: 'Roadmap',
            content: 'Plan the next release',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 2),
            syncStatus: SyncStatus.synced,
            contentHash: 'hash-1',
            deviceId: 'device-1',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sidebar-note-note-1'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(
        tester.getCenter(
            find.byKey(const ValueKey('sidebar-folder-tile-Projects'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(noteRepository.updatedNotes, hasLength(1));
      expect(noteRepository.updatedNotes.single.folderPath, 'Projects');
    },
  );

  testWidgets(
    'desktop sidebar supports dragging a folder into another folder',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Archive',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final gesture = await tester.startGesture(
        tester.getCenter(
            find.byKey(const ValueKey('sidebar-folder-drag-Projects'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(
        tester.getCenter(
            find.byKey(const ValueKey('sidebar-folder-tile-Archive'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(folderRepository.renamedPaths, [('Projects', 'Archive/Projects')]);
      expect(
        find.byKey(const ValueKey('sidebar-folder-tile-Archive/Projects')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'desktop root sidebar menu offers creating notes and folders at root',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final noteRepository = _FakeNoteRepository();
      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.longPress(find.text('Workspace'));
      await tester.pumpAndSettle();

      expect(find.text('New note'), findsAtLeastNWidgets(1));
      expect(find.text('New folder'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'folder deletion asks for confirmation before deleting',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        deleteImpact: const FolderDeleteImpact(
          noteCount: 1,
          childFolderCount: 0,
        ),
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Delete folder?'), findsOneWidget);
      expect(folderRepository.deletedPaths, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(folderRepository.deletedPaths, isEmpty);

      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(folderRepository.deletedPaths, ['Projects']);
    },
  );

  testWidgets(
    'empty folder deletes immediately without confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final folderRepository = _FakeFolderRepository(
        initialFolders: [
          Folder(
            path: 'Projects',
            parentPath: null,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        deleteImpact: const FolderDeleteImpact(
          noteCount: 0,
          childFolderCount: 0,
        ),
      );
      final noteRepository = _FakeNoteRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Delete folder?'), findsNothing);
      expect(folderRepository.deletedPaths, ['Projects']);
      expect(folderRepository.lastDeleteWasRecursive, isFalse);
    },
  );

  testWidgets(
    'note delete snackbar disappears after a few seconds',
    (tester) async {
      final noteRepository = _FakeNoteRepository(
        initialActiveNotes: [
          Note(
            id: 'note-1',
            title: 'Roadmap',
            content: 'Plan the next release',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 2),
            syncStatus: SyncStatus.synced,
            contentHash: 'hash-1',
            deviceId: 'device-1',
          ),
        ],
      );
      final folderRepository = _FakeFolderRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Note actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pump();

      expect(find.text('"Roadmap" deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('"Roadmap" deleted'), findsNothing);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets(
    'sync notice can be dismissed after sync completes',
    (tester) async {
      final noteRepository = _FakeNoteRepository();
      final folderRepository = _FakeFolderRepository();
      final syncController = SyncController(
        runManualSync: RunManualSync(
          noteRepository: noteRepository,
          syncGateway: _FakeSyncGateway(),
          syncStateRepository: _FakeSyncStateRepository(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController:
                AuthController(authService: _SignedInFakeAuthService()),
            syncController: syncController,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await syncController.syncNow();
      await tester.pumpAndSettle();

      expect(find.textContaining('Sync complete'), findsOneWidget);
      expect(find.byTooltip('Dismiss sync notice'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss sync notice'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sync complete'), findsNothing);
    },
  );

  testWidgets(
    'trash is accessed from the workspace instead of the top tab bar',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final noteRepository = _FakeNoteRepository();
      final folderRepository = _FakeFolderRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            createNote: CreateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            createFolder: CreateFolder(repository: folderRepository),
            deleteFolder: DeleteFolder(repository: folderRepository),
            renameFolder: RenameFolder(repository: folderRepository),
            moveNote: MoveNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            updateNote: UpdateNote(
              repository: noteRepository,
              deviceId: 'device-1',
            ),
            deleteNote: DeleteNote(repository: noteRepository),
            restoreNote: RestoreNote(repository: noteRepository),
            searchNotes: SearchNotes(repository: noteRepository),
            folderRepository: folderRepository,
            noteRepository: noteRepository,
            authController: AuthController(authService: _FakeAuthService()),
            syncController: SyncController(
              runManualSync: RunManualSync(
                noteRepository: noteRepository,
                syncGateway: _FakeSyncGateway(),
                syncStateRepository: _FakeSyncStateRepository(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Deleted'), findsNothing);
      expect(find.text('Trash'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('Trash').first);
      await tester.pumpAndSettle();

      expect(find.text('Trash is empty.'), findsOneWidget);
      expect(
          find.widgetWithText(FloatingActionButton, 'New note'), findsNothing);
    },
  );
}

class _FakeAuthService implements AuthService {
  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<AuthSession> signIn() async =>
      const AuthSession(email: 'test@example.com', displayName: 'Test');

  @override
  Future<void> signOut() async {}
}

class _SignedInFakeAuthService implements AuthService {
  @override
  Future<AuthSession?> restoreSession() async =>
      const AuthSession(email: 'test@example.com', displayName: 'Test');

  @override
  Future<AuthSession> signIn() async =>
      const AuthSession(email: 'test@example.com', displayName: 'Test');

  @override
  Future<void> signOut() async {}
}

class _FakeFolderRepository implements FolderRepository {
  _FakeFolderRepository({
    List<Folder> initialFolders = const <Folder>[],
    this.deleteResult = DeleteFolderResult.deleted,
    this.deleteImpact,
  }) : _folders = List<Folder>.from(initialFolders);

  final List<Folder> _folders;
  final DeleteFolderResult deleteResult;
  final FolderDeleteImpact? deleteImpact;
  final List<String> deletedPaths = <String>[];
  final List<(String, String)> renamedPaths = <(String, String)>[];
  final StreamController<List<Folder>> _foldersController =
      StreamController<List<Folder>>.broadcast();
  bool? lastDeleteWasRecursive;

  @override
  Future<void> createFolder(String path) async {}

  @override
  Future<RenameFolderResult> renameFolder(
      String oldPath, String newPath) async {
    renamedPaths.add((oldPath, newPath));
    for (var index = 0; index < _folders.length; index++) {
      final folder = _folders[index];
      if (folder.path == oldPath || folder.path.startsWith('$oldPath/')) {
        final remappedPath = folder.path == oldPath
            ? newPath
            : '$newPath${folder.path.substring(oldPath.length)}';
        final remappedParentPath = folder.parentPath == null
            ? _parentPath(newPath)
            : (folder.parentPath == oldPath ||
                    folder.parentPath!.startsWith('$oldPath/'))
                ? (folder.parentPath == oldPath
                    ? newPath
                    : '$newPath${folder.parentPath!.substring(oldPath.length)}')
                : folder.parentPath;
        _folders[index] = Folder(
          path: remappedPath,
          parentPath: remappedParentPath,
          createdAt: folder.createdAt,
        );
      }
    }
    _folders.sort((a, b) => a.path.compareTo(b.path));
    _foldersController.add(List<Folder>.unmodifiable(_folders));
    return RenameFolderResult.renamed;
  }

  @override
  Future<FolderDeleteImpact?> getDeleteImpact(String path) async =>
      deleteImpact;

  @override
  Future<DeleteFolderResult> deleteFolder(
    String path, {
    bool recursive = false,
  }) async {
    deletedPaths.add(path);
    lastDeleteWasRecursive = recursive;
    return deleteResult;
  }

  @override
  Future<void> ensureFolderExists(String path) async {}

  @override
  Stream<List<Folder>> watchFolders() =>
      Stream<List<Folder>>.multi((controller) {
        controller.add(List<Folder>.unmodifiable(_folders));
        final subscription = _foldersController.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      });

  String? _parentPath(String path) {
    final separatorIndex = path.lastIndexOf('/');
    if (separatorIndex == -1) {
      return null;
    }
    return path.substring(0, separatorIndex);
  }
}

class _FakeNoteRepository implements NoteRepository {
  _FakeNoteRepository({
    List<Note> initialActiveNotes = const <Note>[],
    List<Note> initialDeletedNotes = const <Note>[],
  })  : _activeNotes = List<Note>.from(initialActiveNotes),
        _deletedNotes = List<Note>.from(initialDeletedNotes);

  final List<Note> _activeNotes;
  final List<Note> _deletedNotes;
  final List<Note> updatedNotes = <Note>[];
  final StreamController<List<Note>> _activeController =
      StreamController<List<Note>>.broadcast();
  final StreamController<List<Note>> _deletedController =
      StreamController<List<Note>>.broadcast();

  @override
  Future<void> applyRemoteDeletion(RemoteNote remoteNote) async {}

  @override
  Future<void> create(Note note) async {}

  @override
  Future<Note?> getById(String id) async => null;

  @override
  Future<List<Note>> getActiveNotesForSync() async => const <Note>[];

  @override
  Future<List<Note>> getDeletedNotesForSync() async => const <Note>[];

  @override
  Future<void> markConflict(String id) async {}

  @override
  Future<void> markSynced({
    required String id,
    required DateTime syncedAt,
    required String baseContentHash,
    String? remoteFileId,
  }) async {}

  @override
  Future<void> restore(String id) async {}

  @override
  Future<List<Note>> searchNotes(String query, {String? folderPath}) async =>
      _activeNotes;

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final index = _activeNotes.indexWhere((note) => note.id == id);
    if (index == -1) {
      return;
    }

    final note = _activeNotes.removeAt(index).copyWith(deletedAt: deletedAt);
    _deletedNotes.add(note);
    _activeController.add(List<Note>.unmodifiable(_activeNotes));
    _deletedController.add(List<Note>.unmodifiable(_deletedNotes));
  }

  @override
  Future<void> update(Note note) async {
    updatedNotes.add(note);
    final index = _activeNotes.indexWhere((existing) => existing.id == note.id);
    if (index != -1) {
      _activeNotes[index] = note;
      _activeController.add(List<Note>.unmodifiable(_activeNotes));
    }
  }

  @override
  Future<void> upsertRemoteNote(RemoteNote remoteNote) async {}

  @override
  Stream<List<Note>> watchActiveNotes({String? folderPath}) =>
      Stream<List<Note>>.multi((controller) {
        controller.add(List<Note>.unmodifiable(_activeNotes));
        final subscription = _activeController.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      });

  @override
  Stream<List<Note>> watchDeletedNotes({String? folderPath}) =>
      Stream<List<Note>>.multi((controller) {
        controller.add(List<Note>.unmodifiable(_deletedNotes));
        final subscription = _deletedController.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      });
}

class _FakeSyncGateway implements SyncGateway {
  @override
  Future<RemoteSyncBatch> bootstrap() async => const RemoteSyncBatch(
        notes: <RemoteNote>[],
        nextToken: 'token',
        isFullSnapshot: true,
      );

  @override
  Future<List<RemoteNote>> fetchAllNotes() async => const <RemoteNote>[];

  @override
  Future<RemoteSyncBatch> fetchChangesSince(String token) async =>
      const RemoteSyncBatch(
        notes: <RemoteNote>[],
        nextToken: 'token',
        isFullSnapshot: false,
      );

  @override
  Future<RemoteNote> upsertNote(Note note) async => RemoteNote(
        id: note.id,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        contentHash: note.contentHash,
        deviceId: note.deviceId,
        folderPath: note.folderPath,
        deletedAt: note.deletedAt,
        remoteFileId: 'remote-${note.id}',
      );
}

class _FakeSyncStateRepository implements SyncStateRepository {
  @override
  Future<String?> getDriveSyncToken() async => null;

  @override
  Future<String> getOrCreateDeviceId() async => 'device-1';

  @override
  Future<void> setDriveSyncToken(String token) async {}
}
