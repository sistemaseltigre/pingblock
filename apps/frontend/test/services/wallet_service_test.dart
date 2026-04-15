// Unit tests for WalletUtils (pure logic — no platform code, runs anywhere).
import 'package:flutter_test/flutter_test.dart';
import 'package:pingblock_game/services/wallet_service.dart';

void main() {
  // ── WalletUtils.formatAddress ─────────────────────────────────────────────

  group('WalletUtils.formatAddress', () {
    test('typical 44-char Solana address → first 4 ... last 4', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL';
      // last 4 chars of the 44-char address: 'nEKL'
      expect(WalletUtils.formatAddress(addr), '4Nd1...nEKL');
    });

    test('exact 8-char address is returned unchanged', () {
      const addr = '12345678';
      expect(WalletUtils.formatAddress(addr), '12345678');
    });

    test('address shorter than 8 chars is returned unchanged', () {
      const addr = 'abc';
      expect(WalletUtils.formatAddress(addr), 'abc');
    });

    test('9-char address is trimmed correctly', () {
      const addr = '123456789';
      // first 4 = "1234", last 4 = "6789"
      expect(WalletUtils.formatAddress(addr), '1234...6789');
    });

    test('empty string is returned unchanged', () {
      expect(WalletUtils.formatAddress(''), '');
    });

    test('format always contains "..."', () {
      const addr = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqr'; // 44 chars
      final formatted = WalletUtils.formatAddress(addr);
      expect(formatted, contains('...'));
    });

    test('formatted address has exactly 11 characters for a standard address', () {
      // first4 (4) + "..." (3) + last4 (4) = 11
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL';
      expect(WalletUtils.formatAddress(addr).length, 11);
    });

    test('first 4 chars match address prefix', () {
      const addr = 'XYZAmBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL';
      final formatted = WalletUtils.formatAddress(addr);
      expect(formatted.startsWith('XYZA'), isTrue);
    });

    test('last 4 chars match address suffix', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FZZZZ';
      final formatted = WalletUtils.formatAddress(addr);
      expect(formatted.endsWith('ZZZZ'), isTrue);
    });
  });

  // ── WalletUtils.isValidAddress ─────────────────────────────────────────────

  group('WalletUtils.isValidAddress', () {
    test('valid 44-char base58 address returns true', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL';
      expect(WalletUtils.isValidAddress(addr), isTrue);
    });

    test('empty string returns false', () {
      expect(WalletUtils.isValidAddress(''), isFalse);
    });

    test('address with 0 (zero) returns false — not in base58', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA30EnEKL';
      expect(WalletUtils.isValidAddress(addr), isFalse);
    });

    test('address with O (capital-o) returns false — not in base58', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3OEnEKL';
      expect(WalletUtils.isValidAddress(addr), isFalse);
    });

    test('address with I (capital-i) returns false — not in base58', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3IEnEKL';
      expect(WalletUtils.isValidAddress(addr), isFalse);
    });

    test('address with l (lowercase-L) returns false — not in base58', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3lEnEKL';
      expect(WalletUtils.isValidAddress(addr), isFalse);
    });

    test('address longer than 44 chars returns false', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKLX';
      expect(WalletUtils.isValidAddress(addr), isFalse);
    });

    test('address shorter than 32 chars returns false', () {
      expect(WalletUtils.isValidAddress('TooShort'), isFalse);
    });

    test('address of exactly 32 chars returns true if valid base58', () {
      // 32 valid base58 chars
      const addr = '11111111111111111111111111111111'; // System Program
      expect(WalletUtils.isValidAddress(addr), isTrue);
    });
  });

  // ── Round-trip consistency ─────────────────────────────────────────────────

  group('Round-trip: isValidAddress then formatAddress', () {
    test('formatted address of a valid address is shorter than original', () {
      const addr = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL';
      expect(WalletUtils.isValidAddress(addr), isTrue);
      expect(WalletUtils.formatAddress(addr).length,
          lessThan(addr.length));
    });
  });
}
