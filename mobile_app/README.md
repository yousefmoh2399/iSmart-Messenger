# Mobile App

تطبيق Flutter للموبايل خاص بمسح المستندات، إنشاء PDF، ثم رفعه إلى الـ backend.

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://ismartdbacd.dpdns.org
```

الافتراضي الحالي داخل التطبيق هو `https://ismartdbacd.dpdns.org`.

## Key Features

- login with JWT
- native scan flow
- review, rotate, grayscale, black/white
- multi-page PDF
- pending upload queue
- upload progress
- my files from backend
