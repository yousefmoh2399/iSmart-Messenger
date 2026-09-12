import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  try {
    final response = await dio.get<List<int>>(
      'http://localhost:3000/api/auth/me', 
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Authorization': 'Bearer invalid'}
      )
    );
    print('Did not throw. Status: ${response.statusCode}');
  } catch (e) {
    print('Threw error: $e');
  }
}
