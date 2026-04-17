import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bs58/bs58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

// ── Result ─────────────────────────────────────────────────────────────────

/// Returned by a successful wallet authorize() call.
class WalletConnectionResult {
  /// Full base58-encoded Solana public key, e.g. "4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL"
  final String address;

  /// Opaque token for re-authorization on subsequent app launches.
  final String authToken;

  const WalletConnectionResult(
      {required this.address, required this.authToken});
}

// ── Pure utility helpers ────────────────────────────────────────────────────

/// Address formatting and validation helpers (no platform code — always testable).
class WalletUtils {
  WalletUtils._();

  /// Formats a Solana address for display: first 4 + "..." + last 4 chars.
  /// Returns the full address unchanged if it is 8 chars or shorter.
  ///
  /// Example: "4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL" → "4Nd1...nEKL"
  static String formatAddress(String address) {
    if (address.length <= 8) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }

  /// Returns true if [address] looks like a valid base58 Solana public key
  /// (between 32 and 44 characters, base58 alphabet only).
  static bool isValidAddress(String address) {
    if (address.length < 32 || address.length > 44) return false;
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    return address.split('').every(alphabet.contains);
  }
}

// ── Abstract interface (enables test mocking) ───────────────────────────────

abstract class WalletService {
  /// Launches the wallet picker and returns the authorized account,
  /// or null if the user cancelled or an error occurred.
  Future<WalletConnectionResult?> connect();

  /// Returns current wallet balance in lamports, or null on failure.
  Future<int?> getBalanceLamports(String walletAddress) async => null;

  /// Signs and sends a prebuilt transaction represented in base64,
  /// returning the resulting transaction signature in base58.
  Future<String?> signAndSendTransactionBase64({
    required String transactionBase64,
  }) async =>
      null;
}

// ── Production implementation ───────────────────────────────────────────────

/// Uses [solana_mobile_client] to connect to any MWA-compatible wallet
/// installed on the Android device (Phantom, Solflare, Seed Vault, etc.).
///
/// ### Why `http://localhost` as identityUri
/// Wallet apps show the identityUri in their approval UI but do NOT fetch it
/// for verification. Using `http://localhost` avoids any scheme-mismatch
/// warnings some wallets display for non-https URIs in local/debug builds.
///
class MobileWalletAdapterService implements WalletService {
  // Use a stable https origin for MWA identity metadata.
  static final _identityUri = Uri.parse('https://pingblock.app');
  static const _identityName = 'PingBlock';
  static const _cluster = 'devnet'; // switch to 'mainnet-beta' for prod
  static final _rpcEndpoint = Uri.parse('https://api.devnet.solana.com');
  static const _authorizeTimeout = Duration(seconds: 15);
  static const _retryBackoff = Duration(milliseconds: 350);
  static const _associationSettleDelay = Duration(milliseconds: 700);
  static const _maxAttempts = 2;
  static const _walletActionAttempts = 2;

  String? _lastAuthToken;
  String? _lastAddress;

  @override
  Future<WalletConnectionResult?> connect() async {
    try {
      _debugLog('connect() start');
      final endpointAvailable = await LocalAssociationScenario.isAvailable();
      _debugLog('isAvailable=$endpointAvailable');
      if (!endpointAvailable) {
        throw Exception('No Solana Mobile Wallet Adapter endpoint available');
      }

      Object? lastError;
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        try {
          _debugLog('attempt ${attempt + 1}/$_maxAttempts');
          return await _connectOnce();
        } on Exception catch (e) {
          lastError = e;
          _debugLog('attempt ${attempt + 1} failed: $e');
          if (_isUserRejected(e)) return null;
          if (attempt + 1 < _maxAttempts && _isTransientAssociationError(e)) {
            await Future.delayed(_retryBackoff);
            continue;
          }
          rethrow;
        }
      }

      if (lastError != null) {
        throw Exception('Wallet connect failed: $lastError');
      }
      return null;
    } on Exception catch (e, st) {
      // Log in debug builds.
      assert(() {
        // ignore: avoid_print
        print('[WalletService] connect() error: $e');
        // ignore: avoid_print
        print('[WalletService] connect() stack: $st');
        return true;
      }());
      return null;
    }
  }

  @override
  Future<int?> getBalanceLamports(String walletAddress) async {
    try {
      final payload = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getBalance',
        'params': [
          walletAddress,
          {'commitment': 'processed'},
        ],
      };
      final body = jsonEncode(payload);
      final response = await _postJson(_rpcEndpoint, body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _debugLog('getBalance failed http=${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) return null;
      final value = result['value'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    } catch (e) {
      _debugLog('getBalance error: $e');
      return null;
    }
  }

  @override
  Future<String?> signAndSendTransactionBase64({
    required String transactionBase64,
  }) async {
    if (_lastAuthToken == null || _lastAddress == null) {
      _debugLog('signAndSendTransactionBase64() rejected: no auth session');
      return null;
    }

    Object? lastError;
    for (var attempt = 0; attempt < _walletActionAttempts; attempt++) {
      try {
        final result = await _withReauthorizedClient((client) async {
          final txBytes = base64Decode(transactionBase64);
          final signedAndSent = await client.signAndSendTransactions(
            transactions: [txBytes],
          ).timeout(_authorizeTimeout);

          if (signedAndSent.signatures.isEmpty) return null;
          return base58.encode(signedAndSent.signatures.first);
        });
        if (result != null && result.isNotEmpty) return result;
        return null;
      } on Exception catch (e) {
        lastError = e;
        if (attempt + 1 < _walletActionAttempts &&
            _isTransientAssociationError(e)) {
          await Future.delayed(_retryBackoff);
          continue;
        }
        break;
      }
    }

    _debugLog('signAndSendTransactionBase64 failed: $lastError');
    return null;
  }

  Future<WalletConnectionResult?> _connectOnce() async {
    LocalAssociationScenario? scenario;
    try {
      scenario = await LocalAssociationScenario.create();
      _debugLog('scenario created');

      final clientFuture = scenario.start().timeout(_authorizeTimeout);
      _debugLog('start() requested');
      // ignore: discarded_futures
      scenario.startActivityForResult(null);
      _debugLog('startActivityForResult(null) launched');

      final client = await clientFuture;
      _debugLog('start() completed, client ready');
      await Future.delayed(_associationSettleDelay);
      _debugLog(
          'settle delay completed: ${_associationSettleDelay.inMilliseconds}ms');

      final authResult = await client
          .authorize(
            identityUri: _identityUri,
            identityName: _identityName,
            cluster: _cluster,
          )
          .timeout(_authorizeTimeout);
      _debugLog('authorize() completed. null=${authResult == null}');

      if (authResult == null) return null;

      final address = base58.encode(authResult.publicKey);
      _debugLog('authorize() success address=$address');
      _lastAddress = address;
      _lastAuthToken = authResult.authToken;
      return WalletConnectionResult(
        address: address,
        authToken: authResult.authToken,
      );
    } finally {
      _debugLog('closing scenario');
      await scenario?.close();
      _debugLog('scenario closed');
    }
  }

  Future<T?> _withReauthorizedClient<T>(
    Future<T?> Function(MobileWalletAdapterClient client) action,
  ) async {
    LocalAssociationScenario? scenario;
    try {
      scenario = await LocalAssociationScenario.create();
      _debugLog('reauthorize scenario created');

      final clientFuture = scenario.start().timeout(_authorizeTimeout);
      // ignore: discarded_futures
      scenario.startActivityForResult(null);
      final client = await clientFuture;
      await Future.delayed(_associationSettleDelay);

      final authToken = _lastAuthToken;
      if (authToken == null) return null;

      final authResult = await client
          .reauthorize(
            identityUri: _identityUri,
            identityName: _identityName,
            authToken: authToken,
          )
          .timeout(_authorizeTimeout);
      if (authResult == null) {
        _debugLog('reauthorize returned null');
        return null;
      }

      _lastAuthToken = authResult.authToken;
      _lastAddress = base58.encode(authResult.publicKey);
      return await action(client);
    } finally {
      await scenario?.close();
    }
  }

  Future<_HttpResult> _postJson(Uri uri, String body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(body);
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      return _HttpResult(statusCode: res.statusCode, body: text);
    } finally {
      client.close(force: true);
    }
  }

  bool _isTransientAssociationError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('econnrefused') ||
        s.contains('connection refused') ||
        s.contains('failed establishing a websocket connection') ||
        s.contains('websocketexception') ||
        s.contains('failed to connect') ||
        s.contains('timeoutexception') ||
        s.contains('timed out');
  }

  bool _isUserRejected(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('user rejected') || s.contains('declined');
  }

  static void _debugLog(String msg) {
    assert(() {
      // ignore: avoid_print
      print('[WalletService] $msg');
      return true;
    }());
  }
}

class _HttpResult {
  final int statusCode;
  final String body;

  const _HttpResult({required this.statusCode, required this.body});
}
