enum BaiduRecoveryAction { reconnect, refreshLink }

typedef BaiduSpeedSample = ({
  int bytesPerSecond,
  int windowMs,
  BaiduRecoveryAction? action,
});

/// Measures saved bytes, not the engine's instantaneous speed. One run gets
/// at most two recovery attempts, including across ordinary network retries.
class BaiduTransferRecovery {
  static const _window = Duration(seconds: 15);
  static const _cooldown = Duration(seconds: 90);
  Duration _at = Duration.zero, _warmUntil = Duration.zero;
  Duration _nextRecovery = Duration.zero;
  int _bytes = 0, _peak = 0, _slowWindows = 0;
  int attempts = 0;

  void start(Duration now, int downloaded) {
    _at = now;
    _warmUntil = now + _window;
    _bytes = downloaded;
    _slowWindows = 0;
  }

  BaiduSpeedSample? observe({
    required Duration now,
    required int downloaded,
    required int total,
    required int speedLimit,
    required bool canRecover,
  }) {
    final window = now - _at;
    if (downloaded < _bytes || window.isNegative) {
      start(now, downloaded);
      return null;
    }
    if (window < _window) return null;
    final warmed = _at >= _warmUntil;
    final speed = (downloaded - _bytes) * 1000 ~/ window.inMilliseconds;
    _at = now;
    _bytes = downloaded;
    // A delayed poll after suspension is not a reliable throughput sample.
    final valid = window <= const Duration(seconds: 30);
    if (valid && speed > _peak) _peak = speed;
    var threshold = (_peak ~/ 4).clamp(512 * 1024, 1024 * 1024);
    if (speedLimit > 0) threshold = threshold.clamp(0, speedLimit ~/ 4);
    final eligible =
        valid &&
        canRecover &&
        warmed &&
        now >= _nextRecovery &&
        total - downloaded > 8 * 1024 * 1024 &&
        attempts < 2;
    _slowWindows = eligible && speed < threshold ? _slowWindows + 1 : 0;
    BaiduRecoveryAction? action;
    if (_slowWindows >= 2) {
      action = attempts == 0
          ? BaiduRecoveryAction.reconnect
          : BaiduRecoveryAction.refreshLink;
      attempts++;
      _slowWindows = 0;
      _nextRecovery = now + _cooldown;
    }
    return (
      bytesPerSecond: speed,
      windowMs: window.inMilliseconds,
      action: action,
    );
  }
}
