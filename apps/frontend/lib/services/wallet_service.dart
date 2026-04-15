import 'dart:async';
import 'package:bs58/bs58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

// ── Result ─────────────────────────────────────────────────────────────────

/// Returned by a successful wallet authorize() call.
class WalletConnectionResult {
  /// Full base58-encoded Solana public key, e.g. "4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL"
  final String address;

  /// Opaque token for re-authorization on subsequent app launches.
  final String authToken;

  const WalletConnectionResult({required this.address, required this.authToken});
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
  static const _cluster      = 'devnet'; // switch to 'mainnet-beta' for prod
  static const _authorizeTimeout = Duration(seconds: 15);
  static const _retryBackoff = Duration(milliseconds: 350);
  static const _associationSettleDelay = Duration(milliseconds: 700);
  static const _maxAttempts = 2;

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
      _debugLog('settle delay completed: ${_associationSettleDelay.inMilliseconds}ms');

      final authResult = await client.authorize(
        identityUri: _identityUri,
        identityName: _identityName,
        cluster: _cluster,
      ).timeout(_authorizeTimeout);
      _debugLog('authorize() completed. null=${authResult == null}');

      if (authResult == null) return null;

      final address = base58.encode(authResult.publicKey);
      _debugLog('authorize() success address=$address');
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
