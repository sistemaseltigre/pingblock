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
class MobileWalletAdapterService implements WalletService {
  static const _identityName = 'PingBlock';
  static final _identityUri  = Uri.parse('https://pingblock.app');
  static final _iconUri      = Uri.parse('https://pingblock.app/favicon.ico');
  static const _cluster      = 'mainnet-beta';

  @override
  Future<WalletConnectionResult?> connect() async {
    LocalAssociationScenario? scenario;
    try {
      scenario = await LocalAssociationScenario.create();

      // null → use the currently foregrounded Flutter Activity.
      // The solana_mobile_client plugin resolves this internally via the
      // Flutter plugin binding, which is the standard MWA dApp pattern.
      scenario.startActivityForResult(null);

      final client     = await scenario.start();
      final authResult = await client.authorize(
        identityUri:  _identityUri,
        iconUri:      _iconUri,
        identityName: _identityName,
        cluster:      _cluster,
      );

      if (authResult == null) return null;

      // publicKey is a raw 32-byte Uint8List; encode to the standard base58
      // Solana address string (44 chars for Ed25519 keys).
      final address = base58.encode(authResult.publicKey);

      return WalletConnectionResult(
        address:   address,
        authToken: authResult.authToken,
      );
    } on Exception catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[WalletService] connect() error: $e');
        return true;
      }());
      return null;
    } finally {
      await scenario?.close();
    }
  }
}
