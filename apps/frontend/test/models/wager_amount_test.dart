import 'package:flutter_test/flutter_test.dart';
import 'package:pingblock_game/models/wager_amount.dart';

void main() {
  group('WagerAmountParser.parseSolToLamports', () {
    test('parses valid SOL with decimals', () {
      final result = WagerAmountParser.parseSolToLamports('0.05');
      expect(result.isValid, isTrue);
      expect(result.lamports, 50000000);
    });

    test('rejects empty input', () {
      final result = WagerAmountParser.parseSolToLamports('');
      expect(result.isValid, isFalse);
      expect(result.error, contains('Enter'));
    });

    test('rejects non-numeric input', () {
      final result = WagerAmountParser.parseSolToLamports('abc');
      expect(result.isValid, isFalse);
      expect(result.error, contains('numeric'));
    });

    test('rejects more than 9 decimals', () {
      final result = WagerAmountParser.parseSolToLamports('0.1234567891');
      expect(result.isValid, isFalse);
      expect(result.error, contains('Max 9 decimals'));
    });

    test('rejects values below minimum', () {
      final result = WagerAmountParser.parseSolToLamports('0.001');
      expect(result.isValid, isFalse);
      expect(result.error, contains('Minimum'));
    });

    test('rejects values above maximum', () {
      final result = WagerAmountParser.parseSolToLamports('6');
      expect(result.isValid, isFalse);
      expect(result.error, contains('Maximum'));
    });
  });

  group('WagerAmountParser.lamportsToSolText', () {
    test('formats whole SOL values', () {
      expect(WagerAmountParser.lamportsToSolText(1000000000), '1');
    });

    test('formats decimal SOL values trimming trailing zeros', () {
      expect(WagerAmountParser.lamportsToSolText(1234000000), '1.234');
    });
  });
}
