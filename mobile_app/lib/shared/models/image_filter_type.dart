enum ImageFilterType {
  enhance,
  original,
  lighten,
  gray,
  eco,
  noHandwriting;

  // Legacy backward-compatibility constants
  static const ImageFilterType document = enhance;
  static const ImageFilterType color = original;
  static const ImageFilterType grayscale = gray;
  static const ImageFilterType blackWhite = eco;

  String get nativeKey {
    switch (this) {
      case ImageFilterType.enhance:
        return 'enhance';
      case ImageFilterType.original:
        return 'original';
      case ImageFilterType.lighten:
        return 'lighten';
      case ImageFilterType.gray:
        return 'gray';
      case ImageFilterType.eco:
        return 'eco';
      case ImageFilterType.noHandwriting:
        return 'no_handwriting';
    }
  }

  static ImageFilterType fromKey(String? key) {
    switch (key) {
      case 'original':
      case 'color':
        return ImageFilterType.original;
      case 'lighten':
        return ImageFilterType.lighten;
      case 'gray':
      case 'grayscale':
        return ImageFilterType.gray;
      case 'eco':
      case 'blackWhite':
        return ImageFilterType.eco;
      case 'no_handwriting':
      case 'noHandwriting':
        return ImageFilterType.noHandwriting;
      case 'enhance':
      case 'document':
      default:
        return ImageFilterType.enhance;
    }
  }
}
