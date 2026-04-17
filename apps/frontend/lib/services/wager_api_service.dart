import 'dart:convert';
import 'dart:io';

class PreparedEscrowTx {
  final String intentId;
  final String wagerEscrowPda;
  final String txBase64;
  final String blockhash;
  final int lastValidBlockHeight;

  const PreparedEscrowTx({
    required this.intentId,
    required this.wagerEscrowPda,
    required this.txBase64,
    required this.blockhash,
    required this.lastValidBlockHeight,
  });

  factory PreparedEscrowTx.fromJson(Map<String, dynamic> json) {
    return PreparedEscrowTx(
      intentId: json['intentId']?.toString() ?? '',
      wagerEscrowPda: json['wagerEscrowPda']?.toString() ?? '',
      txBase64: json['txBase64']?.toString() ?? '',
      blockhash: json['blockhash']?.toString() ?? '',
      lastValidBlockHeight:
          int.tryParse(json['lastValidBlockHeight']?.toString() ?? '') ?? 0,
    );
  }
}

class WagerApiService {
  static const String _baseUrl = String.fromEnvironment('BACKEND_URL',
      defaultValue: 'http://localhost:3000');

  Future<PreparedEscrowTx> prepareEscrow({
    required String walletAddress,
    required int lamports,
  }) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('$_baseUrl/wager/prepare-escrow'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'wallet': walletAddress,
        'lamports': lamports,
      }));

      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _readError(text);
        throw Exception(msg);
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid backend response');
      }
      final prepared = PreparedEscrowTx.fromJson(decoded);
      if (prepared.intentId.isEmpty || prepared.txBase64.isEmpty) {
        throw Exception('Missing intentId/txBase64 from backend');
      }
      return prepared;
    } finally {
      client.close(force: true);
    }
  }

  String _readError(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // noop
    }
    return 'Failed to prepare escrow transaction';
  }
}
