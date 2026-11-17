'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import ThemeToggle from './ThemeToggle';
import { Download, Menu, X } from 'lucide-react';

export default function SiteNav() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  const navItems = [
    { href: '/', label: 'الرئيسية' },
    { href: '/#core-features', label: 'إمكانيات النظام' },
    { href: '/windows', label: 'دليل الكمبيوتر' },
    { href: '/mobile', label: 'دليل الموبايل' },
    { href: '/#videos-section', label: 'فيديوهات الشرح' },
    { href: '/faq', label: 'الدعم الفني' },
  ];

  const isActive = (href: string) => {
    if (href === '/') return pathname === '/';
    if (href.startsWith('/#')) return false;
    return pathname === href;
  };

  return (
    <header className="site-nav">
      <div className="container nav-container">
        {/* Brand */}
        <Link href="/" className="nav-brand">
          <img
            src="/assets/images/logo.png"
            alt="iSmart Logo"
            onError={(e) => {
              (e.currentTarget as HTMLImageElement).src = '/assets/images/server-online.png';
            }}
          />
          <div className="nav-brand-text">
            <h1>iSmart Messenger</h1>
            <span>نظام الاتصال الموحد للفروع</span>
          </div>
        </Link>

        {/* Navigation Links */}
        <ul className={`nav-links ${mobileOpen ? 'open' : ''}`}>
          {navItems.map((item) => (
            <li key={item.href} className="nav-item">
              <Link
                href={item.href}
                className={isActive(item.href) ? 'active' : ''}
                onClick={() => setMobileOpen(false)}
              >
                {item.label}
              </Link>
            </li>
          ))}
        </ul>

        {/* Right Actions */}
        <div className="nav-right-actions">
          {/* Apple Theme Toggle (Light / Dark) */}
          <ThemeToggle />

          {/* CTA Download Button */}
          <Link href="/#downloads" className="nav-cta-btn">
            <Download size={15} />
            <span>تحميل البرنامج</span>
          </Link>

          {/* Mobile Drawer Button */}
          <button
            className="mobile-toggle"
            onClick={() => setMobileOpen(!mobileOpen)}
            aria-label="تبديل القائمة"
            type="button"
          >
            {mobileOpen ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </div>
    </header>
  );
}
