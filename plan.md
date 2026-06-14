## Plan: Implement TrueTransfer File Transfer App

### TL;DR
Build a Flutter file transfer utility for Windows + Android that reliably moves files to SMB shares with SHA-256 integrity verification. Core workflow: (1) queue files, (2) connect to SMB, (3) transfer with progress, (4) verify hash, (5) delete source only on success. Use `dart_smb2` for cross-platform SMB access with built-in timeout recovery, persist queue state in JSON for resume capability, and implement transactional safety to prevent data loss.

---

## Steps

**Phase 1: Project Setup & Dependencies** *(sequential, foundational)*
1. Update pubspec.yaml with 5 dependencies: `dart_smb2`, `file_picker`, `crypto`, `path_provider`, `path`
2. Configure platform requirements (Android API 24+, Windows 10+ SDK)
3. Create project directory structure: `lib/{services,models,ui,utils}/`
4. Verify builds succeed with no import errors

**Phase 2: Core Data Models & Persistence** *(depends on Phase 1)*
1. Create `TransferItem` model tracking: source path, remote path, file size, status, transferred bytes, hashes, resume offset, errors
2. Create `TransferQueue` model aggregating all items and metadata
3. Implement `StorageManager` class for JSON serialization to app documents directory
4. Add unit tests for model serialization

**Phase 3: SMB Service Layer** *(depends on Phase 1)*
1. Build `SmBPoolManager` singleton: manages Smb2Pool lifecycle, auto-reconnect on timeouts, worker pool config (4 workers, 30s timeout)
2. Implement `SmBFileTransfer` service with **transactional transfer logic**:
   - Stream copy to remote temp file (.part) with progress callbacks
   - Compute SHA-256 of source file
   - Verify by computing SHA-256 of remote file and comparing
   - Atomic rename only on hash match
   - **Delete source only after verified success** (core safety requirement)
3. Map Smb2Exception error types to UI-friendly handlers (timeout, connection, diskFull, accessDenied, etc.)
4. Add unit tests with mock Smb2Pool

**Phase 4: UI - Workflow Screens** *(depends on Phase 1 & 2 in parallel with Phase 3)*
1. Create `QueueScreen`: file picker, add/remove files, show total size, preview queue
2. Create `ConnectionScreen`: SMB host/share/user/password form, test connection button
3. Create `TransferScreen` (main action): real-time progress bar (overall + per-file), pause/resume, cancel, network error recovery UI, auto-pause on timeout with "Reconnecting..." indicator
4. Create `SummaryScreen`: files transferred, total data moved, storage reclaimed, new transfer button
5. Update main.dart to use new navigation structure
6. Ensure responsive Material 3 design for mobile (Android) and desktop (Windows)

**Phase 5: State Management & Lifecycle** *(depends on all prior phases)*
1. Create `TransferController` class using `ChangeNotifier` to coordinate: queue persistence, SMB pool, file transfer service, UI updates
2. Implement proper initialization on app startup: load queue from JSON, detect incomplete transfers, show resume dialog if needed
3. Implement cleanup on app exit (disconnect SMB pool, save queue state)
4. Wire all screens to TransferController

**Phase 6: Integration & E2E Testing** *(final validation)*
1. Manual test scenarios:
   - Complete transfer → successful deletion of source
   - Interrupted transfer → queue saved, app restart shows resume dialog
   - Network timeout → auto-pause, reconnect, resume automatically
   - Hash mismatch → cleanup remote temp file, show retry option
   - File locked error (EACCES) → graceful notification, retry prompt
2. Verify all error paths handled
3. Benchmark performance on real SMB share

---

## Relevant Files

**To Create (Core Services)**:
- lib/models/transfer_item.dart — TransferItem model with enum status (pending/transferring/verifying/completed/failed/paused)
- lib/models/transfer_queue.dart — Queue aggregation + total bytes tracking
- lib/utils/storage_manager.dart — JSON persistence to app documents directory
- lib/services/smb_pool_manager.dart — Smb2Pool singleton with timeout/reconnect config
- lib/services/smb_file_transfer.dart — **Core transactional logic**: stream transfer, fsync, SHA-256 verification, atomic rename, source deletion ONLY after verified success
- lib/models/smb_exceptions.dart — Custom exception wrapper for Smb2Exception → UI-friendly error types

**To Create (UI)**:
- lib/ui/home_page.dart — Main navigation hub between screens
- lib/ui/screens/queue_screen.dart — File picker, queue management
- lib/ui/screens/connection_screen.dart — SMB credentials form
- lib/ui/screens/transfer_screen.dart — Progress UI with pause/resume/cancel
- lib/ui/screens/summary_screen.dart — Post-transfer metrics

**To Update**:
- pubspec.yaml — Add `dart_smb2: ^0.1.0`, `file_picker: ^6.0.0+`, `crypto: ^3.0.3`, `path_provider: ^2.1.0`, `path: ^1.9.0`
- main.dart — Replace template with real app structure (remove counter logic)
- build.gradle.kts — Set minSdkVersion 24+ (dart_smb2 requires API 24 for Android 7.0+)

---

## Verification

1. ✅ **Dependency resolution**: Run `flutter pub get` with no conflicts
2. ✅ **Platform builds**: Verify `flutter build windows` and `flutter build apk` succeed without FFI errors
3. ✅ **File selection UI**: Test file picker on both Android and Windows
4. ✅ **SMB connectivity**: Connect to test SMB share successfully
5. ✅ **Transactional integrity**: Transfer file, verify hash match, confirm source deleted ONLY after verification passes
6. ✅ **Queue persistence**: Kill app mid-transfer, restart, verify queue restored with resume dialog
7. ✅ **Timeout recovery**: Simulate network drop during transfer, confirm auto-pause and recovery logic engages
8. ✅ **Error handling**: Test file locking (EACCES), disk full (ENOSPC), connection drop scenarios
9. ✅ **Performance metrics**: Verify UI displays accurate progress, total bytes, transfer rate

---

## Decisions & Scope

**Architecture Decisions**:
- ✅ Use `dart_smb2` v0.1.0 (only viable cross-platform SMB library with auto-reconnect)
- ✅ Use fsync() + SHA-256 comparison for integrity (NOT file size alone—aligns with README requirement for partial write detection)
- ✅ JSON persistence for queue (simpler than SQLite, sufficient for resume use case)
- ✅ Material 3 UI (works on both Windows and Android)
- ✅ Sequential file transfer (prioritizes safety over parallelism, aligns with README intent)

**Scope Inclusions** (from README):
- ✅ File/folder selection (queue)
- ✅ SMB transfer with progress tracking
- ✅ Integrity verification (SHA-256 + fsync)
- ✅ Transactional deletion (source deleted ONLY after verified success)
- ✅ Resume capability (queue persists across app restarts)
- ✅ Performance metrics (transfer speed, storage reclaimed)
- ✅ SMB timeout recovery (Smb2Pool auto-reconnect)
- ✅ Partial write detection (hash-based, not size-based)
- ✅ File locking handling (graceful EACCES error paths)

**Scope Exclusions** (out of TrueTransfer spec):
- SMB share browser UI (use text input for now)
- Scheduled transfers
- Bandwidth throttling
- Transfer history database
- Local notifications (can add later)

---

## Further Considerations

1. **Android Permissions**: Ensure AndroidManifest.xml includes:
   - `INTERNET`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`

2. **Large File Handling**: Stream SHA-256 computation to avoid loading entire file into memory for verification step

3. **Sequential Safety**: Queue processes one file at a time (current design). If parallelism needed later, wrap each in separate Smb2Pool worker—do NOT share pool connections between concurrent transfers.

4. **Resume Offset Tracking**: Save `resumeOffset` in queue JSON during transfer; use `writeFileRange()` to resume partial files if dart_smb2 supports it (currently spec'd for full rewrites—test with library docs)
