import 'package:desktop_app/features/chat/utils/chat_attachment_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows extensions when the blocklist is empty', () {
    expect(isChatAttachmentExtensionBlocked('archive.EXE'), isFalse);
  });

  test('uses a generic message for non-Dio errors', () {
    expect(messageFromChatDioError(StateError('failed')), 'تعذر إرسال الملف.');
  });

  test('prefers response messages over Dio exception messages', () {
    final request = RequestOptions(path: '/upload');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        data: {'message': ' الملف كبير جدًا '},
      ),
      message: 'network failure',
    );

    expect(messageFromChatDioError(error), 'الملف كبير جدًا');
  });

  test(
    'falls back through response error, exception, and generic messages',
    () {
      final request = RequestOptions(path: '/upload');
      final responseError = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          data: {'error': 'صيغة غير مدعومة'},
        ),
      );
      final exceptionMessage = DioException(
        requestOptions: request,
        message: ' timed out ',
      );
      final emptyMessage = DioException(requestOptions: request, message: ' ');

      expect(messageFromChatDioError(responseError), 'صيغة غير مدعومة');
      expect(messageFromChatDioError(exceptionMessage), 'timed out');
      expect(messageFromChatDioError(emptyMessage), 'تعذر إرسال الملف.');
    },
  );
}
