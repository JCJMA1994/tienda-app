import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Web: el navegador debe enviar la cookie HttpOnly de sesión (solo a /v1/auth) a la API,
/// que está en otro subdominio. Sin esto, la cookie nunca viaja.
void configureForWeb(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
