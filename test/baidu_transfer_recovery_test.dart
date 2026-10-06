import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/download/baidu_transfer_recovery.dart';

const mib = 1024 * 1024;

void main() {
  test('polling jitter still excludes the first startup window', () {
    final policy = BaiduTransferRecovery()..start(Duration.zero, 0);
    for (var i = 1; i <= 3; i++) {
      final sample = policy.observe(
        now: Duration(milliseconds: i * 15350),
        downloaded: i * mib,
        total: 1024 * mib,
        speedLimit: 0,
        canRecover: true,
      );
      expect(sample!.action, i == 3 ? BaiduRecoveryAction.reconnect : null);
    }
  });

  test('brief dips and startup do not reconnect; sustained low speed does', () {
    final policy = BaiduTransferRecovery()..start(Duration.zero, 0);
    var bytes = 0;
    BaiduSpeedSample sample(int seconds, int speed) {
      bytes += speed * 15;
      return policy.observe(
        now: Duration(seconds: seconds),
        downloaded: bytes,
        total: 1024 * mib,
        speedLimit: 0,
        canRecover: true,
      )!;
    }

    expect(sample(15, 100 * 1024).action, isNull);
    expect(sample(30, 100 * 1024).action, isNull);
    expect(sample(45, 4 * mib).action, isNull);
    expect(sample(60, 700 * 1024).action, isNull);
    expect(sample(75, 700 * 1024).action, BaiduRecoveryAction.reconnect);
  });

  test('retries keep their budget and wait 90 seconds before link refresh', () {
    final policy = BaiduTransferRecovery()..start(Duration.zero, 0);
    var bytes = 0;
    final actions = <BaiduRecoveryAction>[];
    for (var seconds = 15; seconds <= 450; seconds += 15) {
      bytes += mib;
      final sample = policy.observe(
        now: Duration(seconds: seconds),
        downloaded: bytes,
        total: 1024 * mib,
        speedLimit: 0,
        canRecover: true,
      )!;
      if (sample.action != null) {
        actions.add(sample.action!);
        if (actions.length == 2) expect(seconds, greaterThanOrEqualTo(135));
        policy.start(Duration(seconds: seconds), bytes);
      }
    }
    expect(actions, [
      BaiduRecoveryAction.reconnect,
      BaiduRecoveryAction.refreshLink,
    ]);
    expect(policy.attempts, 2);
  });

  test(
    'intentional limit, near end, and non-resumable downloads stay connected',
    () {
      for (final scenario in ['limit', 'tail', 'disabled']) {
        final policy = BaiduTransferRecovery()..start(Duration.zero, 0);
        for (var seconds = 15; seconds <= 90; seconds += 15) {
          final bytes = seconds * 128 * 1024;
          expect(
            policy
                .observe(
                  now: Duration(seconds: seconds),
                  downloaded: bytes,
                  total: scenario == 'tail' ? bytes + mib : 1024 * mib,
                  speedLimit: scenario == 'limit' ? 256 * 1024 : 0,
                  canRecover: scenario != 'disabled',
                )!
                .action,
            isNull,
          );
        }
      }
    },
  );

  test('suspension and reset byte counters cannot look like slow windows', () {
    final policy = BaiduTransferRecovery()..start(Duration.zero, 0);
    BaiduSpeedSample? sample(int seconds, int bytes) => policy.observe(
      now: Duration(seconds: seconds),
      downloaded: bytes,
      total: 1024 * mib,
      speedLimit: 0,
      canRecover: true,
    );
    expect(sample(15, mib)!.action, isNull);
    expect(sample(30, 2 * mib)!.action, isNull);
    expect(sample(180, 3 * mib)!.action, isNull);
    expect(sample(195, 4 * mib)!.action, isNull);
    expect(sample(196, 0), isNull);
    expect(sample(211, mib)!.action, isNull);
    expect(sample(226, 2 * mib)!.action, isNull);
    expect(sample(241, 3 * mib)!.action, BaiduRecoveryAction.reconnect);
  });
}
