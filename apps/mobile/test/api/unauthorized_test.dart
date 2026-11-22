// The three 401 codes of the API (phone-first spec 10 step 1): the phone acts only on the explicit
// ones, and anything else is a session that expired.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/unauthorized.dart';

DioException _answer(int status, Object? body) {
  final request = RequestOptions(path: '/v1/me');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: request,
    response: Response<Object?>(requestOptions: request, statusCode: status, data: body),
  );
}

void main() {
  test('the three codes and a missing body', () {
    expect(unauthorizedOf('device_removed'), Unauthorized.deviceRemoved);
    expect(unauthorizedOf('user_deleted'), Unauthorized.userDeleted);
    expect(unauthorizedOf('unauthenticated'), Unauthorized.expired);
    expect(unauthorizedOf(null), Unauthorized.expired);
    expect(unauthorizedOf('something_new'), Unauthorized.expired);

    expect(
      unauthorizedOfError(_answer(401, {'code': 'device_removed'})),
      Unauthorized.deviceRemoved,
    );
    expect(unauthorizedOfError(_answer(401, '{"code":"user_deleted"}')), Unauthorized.userDeleted);
    expect(unauthorizedOfError(_answer(401, {'code': 'unauthenticated'})), Unauthorized.expired);
    expect(unauthorizedOfError(_answer(401, null)), Unauthorized.expired);
    expect(unauthorizedOfError(_answer(401, 'not json')), Unauthorized.expired);
    // Not a 401: no kind at all.
    expect(unauthorizedOfError(_answer(403, {'code': 'user_deleted'})), isNull);
    expect(unauthorizedOfError(StateError('nope')), isNull);
  });
}
