# dio — recommended approach

Source: [pub.dev/packages/dio](https://pub.dev/packages/dio), read 2026-10-04. Version documented: `dio 5.11.1`.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it for this project. Code samples use the `@riverpod` syntax from [riverpod-guide.md](riverpod-guide.md) and have not been compiled.

---

## 1. Decisions to make once

| Decision | Recommendation | What the docs say |
|---|---|---|
| Instances | One `Dio` for the API, exposed as a keep-alive provider. | "It is recommended to use a singleton of `Dio` in projects." |
| Timeouts | Set connect, send and receive explicitly. | `receiveTimeout` is the gap allowed between received chunks, not a total. |
| Auth header | An interceptor adds it. Token refresh uses `QueuedInterceptor`. | `QueuedInterceptor` runs handlers one at a time, which is what a refresh needs. |
| Errors | Convert `DioException` to an app exception in one function. Repositories throw; they never return `null`. | Every failure, including non-2xx statuses, is a `DioException`. |
| Logging | `LogInterceptor`, debug builds only, added last. | "LogInterceptor should always be the last interceptor added." |
| Cancellation | A `CancelToken` cancelled from `ref.onDispose`. | One token can cancel many requests. |

---

## 2. Setup

```dart
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment('API_BASE_URL'),
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.addAll([
    AuthInterceptor(ref),
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
  ]);

  ref.onDispose(dio.close);
  return dio;
}
```

- Paths passed to `dio.get('/events')` are joined to `baseUrl`.
- By default only 2xx statuses succeed. `validateStatus` changes that; leave it alone so that 4xx and 5xx arrive as errors.
- The default response type is JSON, and large JSON bodies are decoded off the main isolate by the default transformer.

---

## 3. Interceptors

```dart
dio.interceptors.add(
  InterceptorsWrapper(
    onRequest: (options, handler) => handler.next(options),
    onResponse: (response, handler) => handler.next(response),
    onError: (error, handler) => handler.next(error),
  ),
);
```

Each handler must finish with exactly one of `handler.next(...)`, `handler.resolve(response)` or `handler.reject(error)`.

### Auth and token refresh

**Recommendation:**

```dart
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._ref);
  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _ref.read(sessionProvider).accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) return handler.next(err);

    try {
      // Both calls go through a second Dio that has no AuthInterceptor.
      final token = await _ref.read(sessionProvider.notifier).refresh();
      final retry = err.requestOptions
        ..headers['Authorization'] = 'Bearer $token';
      handler.resolve(await _ref.read(plainDioProvider).fetch(retry));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
```

- The refresh call and the retried request go through a separate `Dio` with no auth interceptor. Sending them through the same instance makes them wait on the queue that is waiting for them.
- If the refresh fails, clear the session. The router's redirect then sends the user to login (see [go-router-guide.md](go-router-guide.md), section 12).
- Read the token from memory, not from secure storage, on each request (see [storage-guide.md](storage-guide.md)).

---

## 4. Errors

```dart
try {
  await dio.get('/events');
} on DioException catch (e) {
  e.type;                 // DioExceptionType
  e.response?.statusCode; // set when the server answered
  e.response?.data;
}
```

`DioExceptionType` values: `connectionTimeout`, `sendTimeout`, `receiveTimeout`, `badCertificate`, `badResponse`, `cancel`, `connectionError`, `unknown`. The current docs also list a transform timeout.

**Recommendation:** map once, and keep a wildcard so a new type cannot break the build.

```dart
AppException mapDioException(DioException e) => switch (e.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout => const AppException.timeout(),
  DioExceptionType.connectionError => const AppException.noConnection(),
  DioExceptionType.cancel => const AppException.cancelled(),
  DioExceptionType.badResponse => AppException.server(
    e.response?.statusCode,
    _messageFrom(e.response?.data),
  ),
  _ => AppException.unknown(e.error ?? e.message),
};

Future<T> guardDio<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e, st) {
    Error.throwWithStackTrace(mapDioException(e), st);
  }
}
```

`AppException` is a Freezed union; see [models-codegen-guide.md](models-codegen-guide.md). The UI switches on it to pick a translated message.

In the Riverpod `retry` function, return `null` for `cancelled` and for 4xx server errors; they will not succeed on a second attempt.

---

## 5. Repository and provider

```dart
class EventRepository {
  EventRepository(this._dio);
  final Dio _dio;

  Future<List<Event>> fetchAll({CancelToken? cancelToken}) {
    return guardDio(() async {
      final res = await _dio.get<List<dynamic>>(
        '/events',
        cancelToken: cancelToken,
      );
      return [
        for (final e in res.data!) Event.fromJson(e as Map<String, dynamic>),
      ];
    });
  }
}

@riverpod
Future<List<Event>> events(Ref ref) {
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return ref.watch(eventRepositoryProvider).fetchAll(cancelToken: cancelToken);
}
```

Leaving the screen disposes the provider, which cancels the request. Widgets and Notifiers never touch `Dio` directly.

---

## 6. Uploads and downloads

```dart
final formData = FormData.fromMap({
  'name': 'dio',
  'file': await MultipartFile.fromFile(path, filename: 'upload.jpg'),
});
await dio.post('/upload', data: formData, onSendProgress: (sent, total) {});

await dio.download(url, savePath, onReceiveProgress: (received, total) {});
```

**Docs:** build a new `FormData` and `MultipartFile` for every attempt. Reusing one fails with "Cannot finalize".

---

## 7. Security and platforms

- Never ship `badCertificateCallback: (_, _, _) => true`. It disables TLS verification.
- Certificate pinning is done on `IOHttpClientAdapter` with `validateCertificate`, comparing the SHA-256 fingerprint.
- On web the browser enforces CORS. That is fixed on the server, not in Dio.
- HTTP/2 needs the separate `dio_http2_adapter` plugin.

---

## 8. Review checklist

- [ ] One API `Dio`, created in a keep-alive provider and closed in `onDispose`.
- [ ] All three timeouts set.
- [ ] `LogInterceptor` is last and only in debug builds; no tokens or bodies logged in release.
- [ ] Refresh and retry use a `Dio` without the auth interceptor.
- [ ] `DioException` never leaves the data layer; repositories throw `AppException`.
- [ ] Requests started by a screen are cancelled when its provider is disposed.
- [ ] A new `FormData` per upload attempt.
- [ ] No disabled certificate checks.
