'use client';

import React from 'react';
import { useTheme } from './ThemeContext';
import { Sun, Moon } from 'lucide-react';

export default function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      className="theme-toggle-btn"
      title={theme === 'dark' ? 'التحويل إلى الوضع الفاتح' : 'التحويل إلى الوضع الليلي'}
      aria-label="تبديل الثيم"
      type="button"
    >
      {theme === 'dark' ? (
        <Sun size={19} className="text-amber-400" />
      ) : (
        <Moon size={19} className="text-slate-700" />
      )}
    </button>
  );
}
