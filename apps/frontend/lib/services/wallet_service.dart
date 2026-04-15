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
/// ### Why a cached FlutterEngine is required
/// When the wallet app takes over the foreground, Android pauses/stops our
/// activity. Without a cached engine (see PingBlockApplication.kt), the
/// platform channel that `scenario.start()` awaits is torn down before the
/// wallet finishes connecting, causing an immediate "Disconnected during
/// normal operation" on the wallet side and a null result here.
class MobileWalletAdapterService implements WalletService {
  // Use http://localhost so local/debug builds don't trigger "untrusted" UI
  // in wallet apps. For production, change to https://pingblock.app.
  static final _identityUri = Uri.parse('http://localhost');
  static final _iconUri     = Uri.parse('http://localhost/favicon.ico');
  static const _identityName = 'PingBlock';
  static const _cluster      = 'devnet'; // switch to 'mainnet-beta' for prod

  @override
  Future<WalletConnectionResult?> connect() async {
    LocalAssociationScenario? scenario;
    try {
      scenario = await LocalAssociationScenario.create();

      // Launch the wallet picker.
      // - null  → uses the ActivityResultLauncher pre-registered by the
      //   solana_mobile_client plugin in onAttachedToActivity.
      // - The Flutter engine is cached in PingBlockApplication so the Dart VM
      //   stays alive while the wallet is in the foreground.
      scenario.startActivityForResult(null);

      // Wait for the wallet to connect and establish the encrypted session.
      // Timeout after 60 s — if the user dismisses the wallet without
      // approving, the wallet may not send a disconnect, so we timeout.
      final client = await scenario.start().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException(
          'Wallet did not respond within 60 seconds.',
        ),
      );

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
      // Log in debug builds.
      assert(() {
        // ignore: avoid_print
        print('[WalletService] connect() error: $e');
        return true;
      }());
      return null;
    } finally {
      // Always close cleanly so the wallet app can free its MWA resources.
      await scenario?.close();
    }
  }
}
