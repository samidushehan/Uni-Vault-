import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiMessage {
  const AiMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};
}

class AiService {
  AiService({String? endpoint, http.Client? client})
    : _endpoint = (endpoint ?? _configuredEndpoint).trim(),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const String _configuredEndpoint = String.fromEnvironment(
    'UNIVAULT_AI_ENDPOINT',
  );
  static const Duration _timeout = Duration(seconds: 90);

  final String _endpoint;
  final http.Client _client;
  final bool _ownsClient;

  bool get isConfigured {
    final uri = Uri.tryParse(_endpoint);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  Future<String> generate({
    required String action,
    required String documentName,
    required String context,
    required String prompt,
    List<AiMessage> history = const [],
    int? questionCount,
  }) async {
    if (!isConfigured) {
      throw const AiServiceException(
        'AI is not configured. Deploy the UniVault backend and set UNIVAULT_AI_ENDPOINT when building the app.',
      );
    }
    if (context.trim().isEmpty) {
      throw const AiServiceException(
        'No readable PDF text is available. No AI request was sent.',
      );
    }
    if (prompt.trim().isEmpty) {
      throw const AiServiceException('Enter a question before sending it.');
    }

    final uri = Uri.parse(_endpoint);
    final requestUri = uri.path.endsWith('/api/assistant')
        ? uri
        : uri.replace(
            path: '${uri.path.replaceFirst(RegExp(r'/$'), '')}/api/assistant',
          );

    http.Response response;
    try {
      response = await _client
          .post(
            requestUri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'action': action,
              'documentName': documentName,
              'context': context,
              'prompt': prompt,
              'history': history
                  .map(
                    (message) => {
                      'role': message.role,
                      'text': message.text.length <= 2000
                          ? message.text
                          : message.text.substring(0, 2000),
                    },
                  )
                  .toList(),
              'questionCount': ?questionCount,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AiServiceException(
        'The AI service took too long to respond. Please try again.',
      );
    } on SocketException {
      throw const AiServiceException(
        'Could not reach the AI backend. Check your connection and backend URL.',
      );
    } on HandshakeException {
      throw const AiServiceException(
        'Could not establish a secure connection to the AI backend.',
      );
    } on http.ClientException {
      throw const AiServiceException(
        'Could not reach the AI backend. Check your connection and backend URL.',
      );
    }

    final backendError = _readBackendError(response.body);
    if (response.statusCode == 404 || response.statusCode == 405) {
      throw const AiServiceException(
        'The configured backend does not provide the UniVault AI endpoint.',
      );
    }
    if (response.statusCode == 429) {
      throw AiServiceException(
        backendError ?? 'The AI service is busy or its rate limit was reached. Please try again later.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        backendError ??
            (response.statusCode == 401 || response.statusCode == 403
                ? 'The AI backend rejected the request. Check the Worker configuration.'
                : response.statusCode >= 500
                ? 'The AI backend is temporarily unavailable (${response.statusCode}). Please try again later.'
                : 'The AI request was rejected (${response.statusCode}). Check the PDF text and backend configuration.'),
      );
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['answer'] is! String) {
        throw const FormatException('Missing answer.');
      }
      final answer = (body['answer'] as String).trim();
      if (answer.isEmpty) {
        throw const FormatException('Empty answer.');
      }
      return answer;
    } on FormatException {
      throw const AiServiceException(
        'The AI backend returned an unreadable response. Check its deployment and logs.',
      );
    }
  }

  String? _readBackendError(String body) {
    if (body.length > 2000) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
