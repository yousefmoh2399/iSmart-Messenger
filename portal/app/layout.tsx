import type { Metadata } from 'next';
import './globals.css';
import { ThemeProvider } from '../components/ThemeContext';
import { ToastProvider } from '../components/Toast';
import SiteNav from '../components/SiteNav';
import SiteFooter from '../components/SiteFooter';

export const metadata: Metadata = {
  title: 'iSmart Messenger | بوابة التوزيع وشروحات الفروع',
  description: 'البوابة الرسمية المعتمدة لتحميل وتثبيت برنامج iSmart Messenger لنسختي الكمبيوتر والموبايل لجميع فروع الشركة (50 فرعاً).',
  icons: {
    icon: '/assets/images/logo.png',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ar" dir="rtl" suppressHydrationWarning>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      </head>
      <body>
        <ThemeProvider>
          <ToastProvider>
            <SiteNav />
            <main style={{ flexGrow: 1, display: 'flex', flexDirection: 'column' }}>
              {children}
            </main>
            <SiteFooter />
          </ToastProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
