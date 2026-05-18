import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:avaca/l10n/app_localizations.dart';

class ImageCropper {
  ImageCropper._();

  static Future<bool> open({
    required BuildContext context,
    required String sourceImagePath,
    required String outputImagePath,
    required ValueChanged<String> onCropDone,
  }) {
    final sourceFile = File(sourceImagePath);

    if (!sourceFile.existsSync()) {
      return Future<bool>.value(false);
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _ImageCropperDialog(
          sourceImagePath: sourceImagePath,
          outputImagePath: outputImagePath,
          onCropDone: onCropDone,
        );
      },
    ).then((result) => result ?? false);
  }
}

class _ImageDecodeFailure implements Exception {
  const _ImageDecodeFailure();
}

class _ImageCropperDialog extends StatefulWidget {
  const _ImageCropperDialog({
    required this.sourceImagePath,
    required this.outputImagePath,
    required this.onCropDone,
  });

  final String sourceImagePath;
  final String outputImagePath;
  final ValueChanged<String> onCropDone;

  @override
  State<_ImageCropperDialog> createState() => _ImageCropperDialogState();
}

class _ImageCropperDialogState extends State<_ImageCropperDialog> {
  static const double _maxPreviewSize = 450;
  static const double _dialogHorizontalInset = 24;
  static const double _dialogVerticalInset = 24;
  static const double _dialogPadding = 24;

  img.Image? _originalImage;
  Uint8List? _previewBytes;
  Object? _loadError;
  bool _isSaving = false;

  double _zoom = 1;
  double _x = 0.5;
  double _y = 0.5;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: _dialogHorizontalInset,
        vertical: _dialogVerticalInset,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_dialogPadding),
        child: _buildContent(context),
      ),
    );
  }

  // 讀取圖片並建立預覽資料。
  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.sourceImagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw const _ImageDecodeFailure();
      }

      final bakedImage = img.bakeOrientation(decoded);

      if (!mounted) {
        return;
      }

      setState(() {
        _originalImage = bakedImage;
        _previewBytes = Uint8List.fromList(
          img.encodeJpg(bakedImage, quality: 92),
        );
        _loadError = null;
        _zoom = 1;
        _x = 0.5;
        _y = 0.5;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = error;
      });
    }
  }

  // 依照目前讀取狀態決定顯示錯誤、載入中或裁切內容。
  Widget _buildContent(BuildContext context) {
    if (_loadError != null) {
      return _buildErrorContent(context);
    }

    final originalImage = _originalImage;
    final previewBytes = _previewBytes;

    if (originalImage == null || previewBytes == null) {
      return _buildLoadingContent();
    }

    final mediaSize = MediaQuery.sizeOf(context);
    final isLandscape = mediaSize.width > mediaSize.height;

    final maxDialogWidth = mediaSize.width - (_dialogHorizontalInset * 2);
    final maxDialogHeight = mediaSize.height - (_dialogVerticalInset * 2);

    final imageWidth = originalImage.width.toDouble();
    final imageHeight = originalImage.height.toDouble();

    if (isLandscape) {
      return _buildLandscapeContent(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        maxDialogWidth: maxDialogWidth,
        maxDialogHeight: maxDialogHeight,
        previewBytes: previewBytes,
      );
    }

    return _buildPortraitContent(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      maxDialogWidth: maxDialogWidth,
      maxDialogHeight: maxDialogHeight,
      previewBytes: previewBytes,
    );
  }

  // 顯示圖片讀取失敗內容。
  Widget _buildErrorContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.imageCropLoadErrorTitle),
          const SizedBox(height: 12),
          Text(
            _errorMessage(context),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.close),
            ),
          ),
        ],
      ),
    );
  }

  String _errorMessage(BuildContext context) {
    final error = _loadError;

    if (error is _ImageDecodeFailure) {
      return AppLocalizations.of(context).imageDecodeFailed;
    }

    return error.toString();
  }

  // 顯示圖片載入中的內容。
  Widget _buildLoadingContent() {
    return const SizedBox(
      width: 260,
      height: 140,
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  // 橫向空間中，預覽圖與控制項左右排列。
  Widget _buildLandscapeContent({
    required double imageWidth,
    required double imageHeight,
    required double maxDialogWidth,
    required double maxDialogHeight,
    required Uint8List previewBytes,
  }) {
    const double controlsWidth = 290;
    const double gap = 30;

    final availablePreviewWidth =
        maxDialogWidth - (_dialogPadding * 2) - controlsWidth - gap;
    final availablePreviewHeight = maxDialogHeight - (_dialogPadding * 2);

    final previewMax = _maxDouble(
      100,
      _minDouble(
        _maxPreviewSize,
        _minDouble(availablePreviewWidth, availablePreviewHeight),
      ),
    );

    final displaySize = _calculateDisplaySize(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      previewMax: previewMax,
    );

    final contentWidth = displaySize.width + gap + controlsWidth;
    final contentHeight = _maxDouble(displaySize.height, 260);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxDialogWidth,
        maxHeight: maxDialogHeight,
      ),
      child: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: gap),
              child: _buildPreview(
                displayWidth: displaySize.width,
                displayHeight: displaySize.height,
                previewBytes: previewBytes,
              ),
            ),
            _buildControls(sliderWidth: 220),
          ],
        ),
      ),
    );
  }

  // 直向空間中，預覽圖與控制項上下排列。
  Widget _buildPortraitContent({
    required double imageWidth,
    required double imageHeight,
    required double maxDialogWidth,
    required double maxDialogHeight,
    required Uint8List previewBytes,
  }) {
    const double estimatedControlsHeight = 245;

    final availablePreviewWidth = maxDialogWidth - (_dialogPadding * 2);
    final availablePreviewHeight =
        maxDialogHeight - (_dialogPadding * 2) - estimatedControlsHeight;

    final previewMax = _maxDouble(
      120,
      _minDouble(
        _maxPreviewSize,
        _minDouble(availablePreviewWidth, availablePreviewHeight),
      ),
    );

    final displaySize = _calculateDisplaySize(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      previewMax: previewMax,
    );

    final contentWidth = _maxDouble(displaySize.width, 320);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxDialogWidth,
        maxHeight: maxDialogHeight,
      ),
      child: SingleChildScrollView(
        child: SizedBox(
          width: contentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildPreview(
                displayWidth: displaySize.width,
                displayHeight: displaySize.height,
                previewBytes: previewBytes,
              ),
              const SizedBox(height: 20),
              _buildControls(sliderWidth: 200),
            ],
          ),
        ),
      ),
    );
  }

  // 依圖片比例計算預覽尺寸。
  Size _calculateDisplaySize({
    required double imageWidth,
    required double imageHeight,
    required double previewMax,
  }) {
    if (imageWidth >= imageHeight) {
      return Size(
        previewMax,
        previewMax * (imageHeight / imageWidth),
      );
    }

    return Size(
      previewMax * (imageWidth / imageHeight),
      previewMax,
    );
  }

  // 顯示圖片預覽與裁切框。
  Widget _buildPreview({
    required double displayWidth,
    required double displayHeight,
    required Uint8List previewBytes,
  }) {
    final minDisplayDim = _minDouble(displayWidth, displayHeight);
    final boxSize = minDisplayDim / _zoom;
    final left = _x * (displayWidth - boxSize);
    final top = _y * (displayHeight - boxSize);

    return SizedBox(
      width: displayWidth,
      height: displayHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.memory(
              previewBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: boxSize,
            height: boxSize,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  border: Border.all(
                    color: Colors.blue.shade400,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 顯示裁切參數控制項。
  Widget _buildControls({required double sliderWidth}) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildSliderRow(
          label: l10n.cropZoom,
          width: sliderWidth,
          value: _zoom,
          min: 1,
          max: 10,
          divisions: 90,
          labelText: '${_zoom.toStringAsFixed(1)}x',
          onChanged: _isSaving ? null : _handleZoomChanged,
        ),
        const SizedBox(height: 10),
        _buildSliderRow(
          label: l10n.cropPanX,
          width: sliderWidth,
          value: _x,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: _isSaving ? null : _handleXChanged,
        ),
        const SizedBox(height: 10),
        _buildSliderRow(
          label: l10n.cropPanY,
          width: sliderWidth,
          value: _y,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: _isSaving ? null : _handleYChanged,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSaving ? null : _confirm,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.confirmCrop),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 顯示單一列滑桿。
  Widget _buildSliderRow({
    required String label,
    required double width,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double>? onChanged,
    int? divisions,
    String? labelText,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 5),
        SizedBox(
          width: width,
          child: Slider(
            min: min,
            max: max,
            value: value,
            divisions: divisions,
            label: labelText,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // 更新裁切框大小。
  void _handleZoomChanged(double value) {
    setState(() {
      _zoom = value;
    });
  }

  // 更新裁切框水平位置。
  void _handleXChanged(double value) {
    setState(() {
      _x = value;
    });
  }

  // 更新裁切框垂直位置。
  void _handleYChanged(double value) {
    setState(() {
      _y = value;
    });
  }

  // 依照目前裁切參數輸出圖片。
  Future<void> _confirm() async {
    final originalImage = _originalImage;

    if (originalImage == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final imageWidth = originalImage.width;
      final imageHeight = originalImage.height;
      final minDim = imageWidth < imageHeight ? imageWidth : imageHeight;

      final actualSize = (minDim / _zoom).round().clamp(1, minDim);

      final maxLeft = imageWidth - actualSize;
      final maxTop = imageHeight - actualSize;

      final actualLeft = (_x * maxLeft).round().clamp(0, maxLeft);
      final actualTop = (_y * maxTop).round().clamp(0, maxTop);

      final cropped = img.copyCrop(
        originalImage,
        x: actualLeft,
        y: actualTop,
        width: actualSize,
        height: actualSize,
      );

      final outputFile = File(widget.outputImagePath);

      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(
        img.encodeJpg(cropped, quality: 95),
        flush: true,
      );

      if (!mounted) {
        return;
      }

      widget.onCropDone(widget.outputImagePath);
      Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('裁切過程發生錯誤: $error');

      if (mounted) {
        Navigator.of(context).pop(false);
      }
    }
  }

  double _minDouble(double a, double b) {
    return a < b ? a : b;
  }

  double _maxDouble(double a, double b) {
    return a > b ? a : b;
  }
}