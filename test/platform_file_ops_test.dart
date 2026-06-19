import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truetransfer/utils/platform_file_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.truetransfer/file_ops');
  final List<MethodCall> log = <MethodCall>[];
  bool mockHasPermission = true;

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'deleteFileUri') {
            final uri = methodCall.arguments['uri'] as String;
            if (uri.contains('fail')) {
              throw PlatformException(
                code: 'DELETE_FAILED',
                message: 'Failed to delete',
              );
            }
            return true;
          } else if (methodCall.method == 'checkManageStoragePermission') {
            return mockHasPermission;
          } else if (methodCall.method == 'requestManageStoragePermission') {
            return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PlatformFileOps Tests', () {
    test(
      'deleteOriginalFile should do nothing if identifier is null or empty',
      () async {
        await PlatformFileOps.deleteOriginalFile(null);
        await PlatformFileOps.deleteOriginalFile('');
        expect(log, isEmpty);
      },
    );

    test(
      'deleteOriginalFile should do nothing if identifier is not a content URI',
      () async {
        await PlatformFileOps.deleteOriginalFile(
          '/storage/emulated/0/file.txt',
        );
        expect(log, isEmpty);
      },
    );

    test(
      'deleteOriginalFile should call MethodChannel on Android content URIs',
      () async {
        final success = await PlatformFileOps.deleteOriginalFile(
          'content://media/external/file/123',
        );
        expect(log.length, 1);
        expect(log.first.method, 'deleteFileUri');
        expect(log.first.arguments['uri'], 'content://media/external/file/123');
        expect(success, isTrue);
      },
    );

    test(
      'deleteOriginalFile throws if MethodChannel throws exception',
      () async {
        expect(
          () => PlatformFileOps.deleteOriginalFile(
            'content://media/external/file/fail',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to delete source file'),
            ),
          ),
        );
      },
    );

    test(
      'hasManageStoragePermission should return the correct value from MethodChannel',
      () async {
        mockHasPermission = true;
        final resTrue = await PlatformFileOps.hasManageStoragePermission();
        expect(log.length, 1);
        expect(log.first.method, 'checkManageStoragePermission');
        expect(resTrue, isTrue);

        log.clear();
        mockHasPermission = false;
        final resFalse = await PlatformFileOps.hasManageStoragePermission();
        expect(log.length, 1);
        expect(log.first.method, 'checkManageStoragePermission');
        expect(resFalse, isFalse);
      },
    );

    test(
      'requestManageStoragePermission should call the correct MethodChannel',
      () async {
        await PlatformFileOps.requestManageStoragePermission();
        expect(log.length, 1);
        expect(log.first.method, 'requestManageStoragePermission');
      },
    );
  });
}
