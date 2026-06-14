# TrueTransfer

**TrueTransfer** is a reliable, integrity-focused file transfer utility built with Flutter. Designed for users who prioritize data integrity, TrueTransfer ensures that your files are bit-perfectly copied to your destination—specifically optimized for network shares (SMB)—before safely purging the source files to reclaim storage space.

## Key Features

* **Integrity Verification:** Every file is verified using SHA-256 hashing post-transfer to ensure the destination file matches the source exactly.
* **SMB-Optimized:** Built with error-handling logic tailored for SMB network shares, ensuring graceful recovery from common network timeouts or dropped connections.
* **Transactional Safety:** The "Delete Source" operation is programmatically locked behind a successful verification state. If the copy isn't perfect, the source remains untouched.
* **Resume Capability:** Transfers interrupted by network instability or app closure can be resumed, skipping already-verified files.
* **Performance Metrics:** Real-time progress tracking and post-transfer summary of data moved and storage reclaimed.

## How it Works

1. **Queue:** Select the files or folders you wish to move.
2. **Transfer:** TrueTransfer copies your data to your target SMB share.
3. **Verify:** The app computes a hash of the destination file and compares it against the source.
4. **Cleanup:** Only upon a successful match is the original file deleted from your device.

## Integrating SMB into your Use Cases

Since TrueTransfer targets SMB, use cases should account for SMB characteristics such as file locking, latency, and session timeouts.

### Case: SMB Timeout Recovery

*Context:* SMB shares often disconnect due to mobile power management or network handoffs.

*Refined Logic:* The Flutter service should detect `IOException` or `SocketException` specifically tied to SMB access. Instead of failing the transfer, the app should automatically pause, re-establish the SMB session, and verify the status of the last partially written file before resuming the queue.

### Case: Partial Write Detection

*Context:* SMB transfers can sometimes produce a file with the expected size but incomplete content after a connection drop.

*Refined Logic:* File size alone is not a reliable integrity signal over SMB. Hash verification is the primary safeguard, and source-file deletion must be strictly blocked unless hash verification returns `true`.

### Case: Handling File Locks

*Context:* The SMB share may be accessed by other processes (for example, a NAS backup agent), causing write failures.

*Refined Logic:* Add an explicit "Access Denied / File Locked" exception path that notifies the user to retry later rather than force-writing the file.
