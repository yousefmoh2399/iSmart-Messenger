'use client';

import React, { useState } from 'react';
import { useToast } from './Toast';
import { Copy, Check } from 'lucide-react';

interface ServerIpBarProps {
  ip?: string;
  label?: string;
  sublabel?: string;
}

export default function ServerIpBar({
  ip = 'http://172.17.100.253:5000',
  label = 'عنوان خادم المراسلات المعتمد (Server Host)',
  sublabel = 'أدخل هذا العنوان في إعدادات الاتصال بالبرنامج للربط بالشبكة الداخلية',
}: ServerIpBarProps) {
  const { showToast } = useToast();
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(ip).then(() => {
        setCopied(true);
        showToast('تم نسخ عنوان السيرفر بنجاح!');
        setTimeout(() => setCopied(false), 2000);
      }).catch(() => {
        fallbackCopy();
      });
    } else {
      fallbackCopy();
    }
  };

  const fallbackCopy = () => {
    const el = document.createElement('textarea');
    el.value = ip;
    document.body.appendChild(el);
    el.select();
    document.execCommand('copy');
    document.body.removeChild(el);
    setCopied(true);
    showToast('تم نسخ عنوان السيرفر بنجاح!');
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="server-bar">
      <div className="server-bar-info">
        <div className="server-dot" title="الخادم متصل ونشط" />
        <div className="server-bar-text">
          <h4>{label}</h4>
          <p>{sublabel}</p>
        </div>
      </div>

      <div className="server-input-group">
        <div className="server-code-box" id="serverIpBox">
          {ip}
        </div>
        <button
          className="btn-mini-copy"
          onClick={handleCopy}
          type="button"
          style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}
        >
          {copied ? <Check size={14} /> : <Copy size={14} />}
          <span>{copied ? 'تم النسخ' : 'نسخ العنوان'}</span>
        </button>
      </div>
    </div>
  );
}
