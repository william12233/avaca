import 'package:flutter/material.dart';

class AppSnackBar {
  AppSnackBar._();

  static const _maxWidth = 400.0;
  static const _asciiUnitWidth = 10;
  static const _nonAsciiUnitWidth = 20;
  static const _widthPadding = 5;

  static const _duration = Duration(milliseconds: 3000);
  static const _contentPadding = EdgeInsets.only(
    left: 5,
    top: 4,
    right: 5,
    bottom: 6,
  );
  static const _textStyle = TextStyle(color: Colors.white);

  // 依照文字內容估算浮動提示的寬度，避免提示過寬。
  static double _calculateWidth(String message) {
    final width = message.runes.fold<int>(
      0,
      (total, char) => total + _characterWidth(char),
    );

    return (width + _widthPadding).clamp(0, _maxWidth).toDouble();
  }

  // ASCII 與非 ASCII 字元使用不同寬度，讓中英文訊息都能維持接近原本的尺寸。
  static int _characterWidth(int char) {
    return char < 128 ? _asciiUnitWidth : _nonAsciiUnitWidth;
  }

  // 顯示新的提示前先收起目前提示，讓畫面上一次只保留一個提示。
  static void _show(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: _textStyle,
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: _duration,
        width: _calculateWidth(message),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: _contentPadding,
      ),
    );
  }

  // 顯示成功提示。
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, Colors.green.shade700);
  }

  // 顯示錯誤提示。
  static void showError(BuildContext context, String message) {
    _show(context, message, Colors.red);
  }

  // 顯示一般提示。
  static void showInfo(BuildContext context, String message) {
    _show(context, message, Colors.blueGrey.shade700);
  }
}