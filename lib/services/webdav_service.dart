import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../models/media_item.dart';

class WebDavService {
  WebDavService(
      {required this.baseUrl, required this.username, required this.password})
      : _dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30)));

  final String baseUrl;
  final String username;
  final String password;
  final Dio _dio;

  Future<List<MediaItem>> list(String path) async {
    final root = _join(baseUrl, path);
    final response = await _dio.request<String>(
      root,
      options: Options(
          method: 'PROPFIND',
          responseType: ResponseType.plain,
          headers: {
            'Depth': '1',
            'Content-Type': 'application/xml; charset=utf-8',
            if (username.isNotEmpty || password.isNotEmpty)
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('$username:$password'))}',
          }),
      data:
          '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>',
    );
    final document = XmlDocument.parse(response.data ?? '');
    final entries = <MediaItem>[];
    for (final node
        in document.findAllElements('response', namespace: 'DAV:')) {
      final href = node.getElement('href', namespace: 'DAV:')?.innerText;
      if (href == null) continue;
      final decoded = Uri.decodeComponent(href);
      final current = Uri.parse(root).path;
      if (_normalizePath(decoded) == _normalizePath(current)) continue;
      final props = node.findAllElements('prop', namespace: 'DAV:');
      final prop = props.isEmpty ? null : props.first;
      final isDirectory =
          node.findAllElements('collection', namespace: 'DAV:').isNotEmpty;
      final name = Uri.decodeComponent(
          decoded.replaceAll(RegExp(r'/$'), '').split('/').last);
      if (name.isEmpty) continue;
      final length = int.tryParse(prop
                  ?.getElement('getcontentlength', namespace: 'DAV:')
                  ?.innerText ??
              '') ??
          0;
      final modifiedText =
          prop?.getElement('getlastmodified', namespace: 'DAV:')?.innerText;
      final modified = _parseDate(modifiedText);
      entries.add(MediaItem(
          name: name,
          url: _absolute(href),
          size: length,
          modified: modified,
          isDirectory: isDirectory));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _absolute(String href) => Uri.parse(baseUrl).resolve(href).toString();
  String _join(String base, String path) =>
      Uri.parse(base.endsWith('/') ? base : '$base/')
          .resolve(path.replaceFirst(RegExp(r'^/+'), ''))
          .toString();
  String _normalizePath(String path) => path.replaceAll(RegExp(r'/$'), '');

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    final match = RegExp(
            r'\w+,\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(value);
    if (match == null) return null;
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12
    };
    final month = months[match.group(2)];
    if (month == null) return null;
    return DateTime.utc(
        int.parse(match.group(3)!),
        month,
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!));
  }
}
