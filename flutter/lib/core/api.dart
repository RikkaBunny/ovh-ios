import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'models.dart';

const qaEnabled = kDebugMode && bool.fromEnvironment('OVH_QA');

class ApiResult {
  final dynamic value;
  final List<String> notices;
  const ApiResult(this.value, [this.notices = const []]);
}

class PanelApi {
  final http.Client client;
  PanelApi({http.Client? client}) : client = client ?? createClient();
  static http.Client createClient() {
    final transport = HttpClient();
    // Only the explicitly selected Debug fixture can use its local self-signed certificate.
    // Release and every non-local endpoint keep standard certificate validation.
    if (qaEnabled) {
      transport.badCertificateCallback = (_, host, port) =>
          host == 'localhost' && port == 16443;
    }
    return IOClient(transport);
  }

  http.Request makeRequest(
    Connection connection,
    String path, {
    String? account,
    String method = 'GET',
    Json? body,
    Map<String, String> query = const {},
  }) {
    if (!path.startsWith('/') || path.contains('://')) {
      throw const PanelException('接口路径无效');
    }
    final uri = Uri.parse('${connection.address}/api$path');
    final parameters = {...uri.queryParameters, ...query}..remove('account');
    if (account != null && account.isNotEmpty) parameters['account'] = account;
    final request = http.Request(
      method,
      uri.replace(queryParameters: parameters),
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    request.headers[connection.deviceToken
        ? 'Authorization'
        : 'X-API-Key'] = connection.deviceToken
        ? 'Bearer ${connection.secret}'
        : connection.secret;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return request;
  }

  Future<ApiResult> request(
    Connection connection,
    String path, {
    String? account,
    String method = 'GET',
    Json? body,
    Map<String, String> query = const {},
  }) => send(
    makeRequest(
      connection,
      path,
      account: account,
      method: method,
      body: body,
      query: query,
    ),
  );
  Future<ApiResult> send(http.Request request) async {
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 60)),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode == 401) {
      throw const PanelException('设备授权已失效，请重新连接', 401);
    }
    dynamic value;
    try {
      value = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const PanelException('面板数据格式无法识别，请检查地址或版本');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PanelException(
        text(
          object(value)['message'],
          text(object(value)['error'], '请求失败（HTTP ${response.statusCode}）'),
        ),
        response.statusCode,
      );
    }
    if (object(value)['success'] == false ||
        object(value)['status'] == 'error') {
      throw PanelException(
        text(object(value)['error'], text(object(value)['message'], '操作未成功')),
      );
    }
    final notices = <String>[];
    if ((response.headers['x-partial-failures'] ?? '0') != '0') {
      notices.add('部分明细未能获取，请重试');
    }
    if (response.headers['x-cache-warning']?.isNotEmpty == true) {
      notices.add(cacheWarning(response.headers['x-cache-warning']!));
    }
    if (response.headers['x-subsidiary-mismatch'] == '1') {
      notices.add('账户所属站点与当前区域不一致，请检查账户设置');
    }
    return ApiResult(value, notices);
  }

  Future<Connection> pair(String address, String input, String name) async {
    final origin = Connection.validated(address, 'validation').address;
    final code = PairingInput.normalizeCode(input), cleanName = name.trim();
    if (cleanName.isEmpty || utf8.encode(cleanName).length > 100) {
      throw const PanelException('设备名称不能为空或过长');
    }
    final request = http.Request('POST', Uri.parse('$origin/api/app/pair'))
      ..followRedirects = false;
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    request.body = jsonEncode({'code': code, 'deviceName': cleanName});
    final result = object((await send(request)).value);
    if (result['success'] != true ||
        result['token'] is! String ||
        result['deviceId'] is! int) {
      throw const PanelException('面板未返回有效的设备令牌');
    }
    return Connection.validated(
      origin,
      result['token'],
      deviceToken: true,
      deviceId: result['deviceId'],
    );
  }

  Future<ApiResult> stock(Account account, Connection connection) {
    final base = {
      'EU': 'https://eu.api.ovh.com',
      'CA': 'https://ca.api.ovh.com',
      'US': 'https://api.us.ovhcloud.com',
    }[account.region]!;
    final url = qaEnabled && connection.address == 'https://localhost:16443'
        ? 'https://localhost:16443/qa/availability?region=${account.region}'
        : '$base/v1/dedicated/server/datacenter/availabilities';
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    return send(request); // No panel authentication headers on public OVH APIs.
  }

  void close() => client.close();
}
