import 'dart:io';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';

/// 顯示單一演員資料的卡片。
class ActressCard extends StatelessWidget {
  const ActressCard({
    super.key,
    required this.name,
    this.imgPath,
    this.onTap,
  });

  /// 演員名稱。
  final String name;

  /// 演員圖片的本機檔案路徑。
  final String? imgPath;

  /// 點擊卡片時執行的回呼。
  final VoidCallback? onTap;

  static const double _cardBorderRadius = 12;
  static const double _imageBorderRadius = 8;
  static const double _cardPadding = 10;
  static const double _spacingBetweenImageAndName = 5;
  static const double _placeholderIconSize = 40;
  static const double _placeholderTextSize = 10;
  static const double _nameTextSize = 16;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.topCenter,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardBorderRadius),
          side: BorderSide(
            width: 1,
            color: colorScheme.outline,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_cardBorderRadius),
          child: Padding(
            padding: const EdgeInsets.all(_cardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildImageBox(context),
                const SizedBox(height: _spacingBetweenImageAndName),
                _buildNameText(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 建立固定為正方形的圖片區塊。
  Widget _buildImageBox(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: _buildCoverContent(context),
    );
  }

  /// 根據圖片路徑決定顯示圖片或預設佔位內容。
  Widget _buildCoverContent(BuildContext context) {
    final path = imgPath;

    if (path != null && path.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_imageBorderRadius),
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildEmptyImagePlaceholder(context);
          },
        ),
      );
    }

    return _buildEmptyImagePlaceholder(context);
  }

  /// 建立沒有圖片或圖片讀取失敗時的佔位內容。
  Widget _buildEmptyImagePlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_imageBorderRadius),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported,
            size: _placeholderIconSize,
            color: colorScheme.onSurface,
          ),
          Text(
            l10n.noPhoto,
            style: TextStyle(
              fontSize: _placeholderTextSize,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// 建立卡片底部的演員名稱文字。
  Widget _buildNameText(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: _nameTextSize,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}