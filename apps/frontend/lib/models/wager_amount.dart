class WagerAmountConfig {
  WagerAmountConfig._();

  static const int lamportsPerSol = 1000000000;
  static const int maxDecimals = 9;
  static const int minLamports = 10000000; // 0.01 SOL
  static const int maxLamports = 5000000000; // 5.0 SOL
}

class WagerAmountResult {
  final int? lamports;
  final String? error;

  const WagerAmountResult._({this.lamports, this.error});

  bool get isValid => lamports != null && error == null;

  factory WagerAmountResult.ok(int lamports) =>
      WagerAmountResult._(lamports: lamports);

  factory WagerAmountResult.fail(String error) =>
      WagerAmountResult._(error: error);
}

class WagerAmountParser {
  WagerAmountParser._();

  static final RegExp _numeric = RegExp(r'^\d+(\.\d+)?$');

  static WagerAmountResult parseSolToLamports(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return WagerAmountResult.fail('Enter a SOL amount');
    if (!_numeric.hasMatch(input)) {
      return WagerAmountResult.fail('Only numeric SOL values are allowed');
    }

    final parts = input.split('.');
    final whole = parts[0];
    final decimal = parts.length == 2 ? parts[1] : '';
    if (decimal.length > WagerAmountConfig.maxDecimals) {
      return WagerAmountResult.fail(
          'Max ${WagerAmountConfig.maxDecimals} decimals');
    }

    final paddedDecimal = decimal.padRight(WagerAmountConfig.maxDecimals, '0');
    final wholeLamports = int.tryParse(whole);
    final decimalLamports = int.tryParse(paddedDecimal);
    if (wholeLamports == null || decimalLamports == null) {
      return WagerAmountResult.fail('Invalid SOL amount');
    }

    final lamports =
        (wholeLamports * WagerAmountConfig.lamportsPerSol) + decimalLamports;
    if (lamports < WagerAmountConfig.minLamports) {
      return WagerAmountResult.fail('Minimum wager is 0.01 SOL');
    }
    if (lamports > WagerAmountConfig.maxLamports) {
      return WagerAmountResult.fail('Maximum wager is 5 SOL in devnet');
    }
    return WagerAmountResult.ok(lamports);
  }

  static String lamportsToSolText(int lamports) {
    final whole = lamports ~/ WagerAmountConfig.lamportsPerSol;
    final fraction = (lamports % WagerAmountConfig.lamportsPerSol)
        .toString()
        .padLeft(WagerAmountConfig.maxDecimals, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    if (fraction.isEmpty) return '$whole';
    return '$whole.$fraction';
  }
}
