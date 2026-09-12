enum ImageFilterType {
  document('مسح ذكي'),
  color('ألوان'),
  grayscale('رمادي'),
  blackWhite('أبيض وأسود');

  const ImageFilterType(this.label);

  final String label;
}
