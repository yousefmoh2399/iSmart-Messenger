'use client';

import React, { useState, useEffect } from 'react';
import {
  Shield,
  Activity,
  Sliders,
  Network,
  UploadCloud,
  Lock,
  LogOut,
  RefreshCw,
  Power,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  Laptop,
  Smartphone,
  Plus,
  Trash2,
  Save,
  Server,
  Download,
  Clock,
  Eye,
  EyeOff,
} from 'lucide-react';
import TopStrip from '@/components/TopStrip';

interface ActiveDownload {
  id: string;
  ip: string;
  subnet: string;
  branchName: string;
  fileKey: 'windows' | 'mobile';
  fileName: string;
  startedAt: number;
  lastActiveAt: number;
  bytesTransferred: number;
  totalBytes: number;
  speedLimitKBps: number;
  status: string;
}

export default function AdminPage() {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean | null>(null);
  const [pinInput, setPinInput] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [loginError, setLoginError] = useState('');
  const [loginLoading, setLoginLoading] = useState(false);

  // Admin Data State
  const [activeTab, setActiveTab] = useState<'live' | 'toggles' | 'vpn' | 'branches' | 'files' | 'security'>('live');
  const [config, setConfig] = useState<any>(null);
  const [activeDownloads, setActiveDownloads] = useState<ActiveDownload[]>([]);
  const [systemStats, setSystemStats] = useState<any>(null);
  const [loadingStats, setLoadingLoading] = useState(false);
  const [saveStatus, setSaveStatus] = useState<{ message: string; isError?: boolean } | null>(null);

  // File Upload State
  const [windowsFile, setWindowsFile] = useState<File | null>(null);
  const [windowsVersion, setWindowsVersion] = useState('');
  const [mobileFile, setMobileFile] = useState<File | null>(null);
  const [mobileVersion, setMobileVersion] = useState('');
  const [uploadingWindows, setUploadingWindows] = useState(false);
  const [uploadingMobile, setUploadingMobile] = useState(false);
  const [uploadMessage, setUploadMessage] = useState<string | null>(null);

  // New Whitelist / Branch Input
  const [newWhitelistSubnet, setNewWhitelistSubnet] = useState('');
  const [newBranchSubnet, setNewBranchSubnet] = useState('');
  const [newBranchName, setNewBranchName] = useState('');

  // New PIN State
  const [newPin, setNewPin] = useState('');
  const [confirmPin, setConfirmPin] = useState('');

  // Fetch status from API
  const fetchStatus = async (isBackground = false) => {
    try {
      if (!isBackground) setLoadingLoading(true);
      const res = await fetch('/api/admin/status', {
        cache: 'no-store',
        headers: { 'x-admin-token': 'authenticated_admin' },
      });
      if (res.status === 401) {
        if (typeof window !== 'undefined') {
          localStorage.removeItem('ismart_admin_token');
        }
        setIsAuthenticated(false);
        return;
      }
      const data = await res.json();
      if (data.success) {
        setIsAuthenticated(true);
        setConfig(data.config);
        setActiveDownloads(data.activeDownloads || []);
        setSystemStats(data.system);
        if (!windowsVersion && data.config?.windows?.version) {
          setWindowsVersion(data.config.windows.version);
        }
        if (!mobileVersion && data.config?.mobile?.version) {
          setMobileVersion(data.config.mobile.version);
        }
      } else {
        if (typeof window !== 'undefined') {
          localStorage.removeItem('ismart_admin_token');
        }
        setIsAuthenticated(false);
      }
    } catch (err) {
      if (!isBackground) {
        setIsAuthenticated(false);
      }
    } finally {
      if (!isBackground) setLoadingLoading(false);
    }
  };

  useEffect(() => {
    fetchStatus();
  }, []);

  // Auto-refresh active downloads every 4 seconds ONLY when on the 'live' tab
  useEffect(() => {
    if (!isAuthenticated || activeTab !== 'live') return;
    const interval = setInterval(() => {
      fetchStatus(true);
    }, 4000);
    return () => clearInterval(interval);
  }, [isAuthenticated, activeTab]);

  // Handle Login
  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoginError('');
    setLoginLoading(true);

    try {
      const res = await fetch('/api/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pin: pinInput }),
      });
      const data = await res.json();
      if (data.success) {
        if (typeof window !== 'undefined') {
          localStorage.setItem('ismart_admin_token', 'authenticated_admin');
        }
        setIsAuthenticated(true);
        setPinInput('');
        await fetchStatus(false);
      } else {
        setLoginError(data.message || 'رمز الدخول غير صحيح!');
      }
    } catch (err) {
      setLoginError('فشل الاتصال بالخادم.');
    } finally {
      setLoginLoading(false);
    }
  };

  // Handle Logout
  const handleLogout = async () => {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('ismart_admin_token');
    }
    await fetch('/api/admin/logout', {
      method: 'POST',
      headers: { 'x-admin-token': 'authenticated_admin' },
    });
    setIsAuthenticated(false);
    setConfig(null);
  };

  // Save Configuration Updates
  const handleSaveConfig = async (partialUpdates: any) => {
    setSaveStatus(null);
    // Optimistically update config in state to prevent toggle jumping
    setConfig((prev: any) => (prev ? { ...prev, ...partialUpdates } : prev));
    try {
      const res = await fetch('/api/admin/config', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-admin-token': 'authenticated_admin',
        },
        body: JSON.stringify(partialUpdates),
      });
      const data = await res.json();
      if (data.success) {
        setConfig(data.config);
        setSaveStatus({ message: 'تم حفظ وتطبيق التعديلات بنجاح على كافة الفروع!' });
        setTimeout(() => setSaveStatus(null), 4000);
      } else {
        setSaveStatus({ message: data.message || 'فشل حفظ الإعدادات.', isError: true });
      }
    } catch (err: any) {
      setSaveStatus({ message: 'حدث خطأ أثناء حفظ الإعدادات.', isError: true });
    }
  };

  // Kill Download Session
  const handleKillSession = async (sessionId: string) => {
    try {
      const res = await fetch('/api/admin/kill-download', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-admin-token': 'authenticated_admin',
        },
        body: JSON.stringify({ sessionId }),
      });
      const data = await res.json();
      if (data.success) {
        setActiveDownloads(data.activeDownloads || []);
        setSaveStatus({ message: data.message });
        setTimeout(() => setSaveStatus(null), 3000);
      }
    } catch (err) {
      alert('فشل إنهاء الجلسة.');
    }
  };

  // Handle File Upload (Windows or Mobile)
  const handleFileUpload = async (type: 'windows' | 'mobile') => {
    const file = type === 'windows' ? windowsFile : mobileFile;
    const version = type === 'windows' ? windowsVersion : mobileVersion;

    if (!file) {
      alert('برجاء اختيار الملف أولاً.');
      return;
    }

    if (type === 'windows') setUploadingWindows(true);
    else setUploadingMobile(true);
    setUploadMessage(null);

    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('type', type);
      formData.append('version', version);

      const res = await fetch('/api/admin/upload', {
        method: 'POST',
        headers: { 'x-admin-token': 'authenticated_admin' },
        body: formData,
      });
      const data = await res.json();
      if (data.success) {
        setConfig(data.config);
        setUploadMessage(data.message);
        if (type === 'windows') setWindowsFile(null);
        else setMobileFile(null);
      } else {
        alert(data.message || 'فشل رفع الملف.');
      }
    } catch (err) {
      alert('حدث خطأ أثناء رفع الملف للخادم.');
    } finally {
      if (type === 'windows') setUploadingWindows(false);
      else setUploadingMobile(false);
    }
  };

  // Format Helper
  const formatBytes = (bytes: number) => {
    if (!bytes || bytes === 0) return '0 MB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  };

  // -------------------------------------------------------------
  // LOGIN SCREEN
  // -------------------------------------------------------------
  if (isAuthenticated === false) {
    return (
      <div
        style={{
          minHeight: '80vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '24px',
          direction: 'rtl',
        }}
      >
        <div
          style={{
            maxWidth: '420px',
            width: '100%',
            backgroundColor: 'var(--bg-card, #ffffff)',
            borderRadius: '24px',
            padding: '36px 32px',
            boxShadow: '0 12px 32px rgba(0,0,0,0.08)',
            border: '1px solid var(--hairline, rgba(60,60,67,0.12))',
            textAlign: 'center',
          }}
        >
          <div
            style={{
              width: '64px',
              height: '64px',
              borderRadius: '20px',
              backgroundColor: 'var(--apple-blue-soft, rgba(0, 122, 255, 0.08))',
              color: 'var(--apple-blue, #007aff)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              margin: '0 auto 20px',
            }}
          >
            <Shield size={32} />
          </div>

          <h2 style={{ fontSize: '1.4rem', fontWeight: 800, margin: '0 0 8px' }}>
            لوحة الإدارة والتحكم في الفروع
          </h2>
          <p style={{ fontSize: '0.88rem', color: 'var(--label-secondary, #8e8e93)', margin: '0 0 24px' }}>
            أدخل رمز الدخول السري (Admin PIN) للتحكم في بوابات التحميل وسياسات الـ VPN.
          </p>

          {loginError && (
            <div
              style={{
                backgroundColor: 'rgba(255, 59, 48, 0.1)',
                color: 'var(--apple-red, #ff3b30)',
                borderRadius: '12px',
                padding: '10px 14px',
                fontSize: '0.85rem',
                fontWeight: 600,
                marginBottom: '16px',
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                justifyContent: 'center',
              }}
            >
              <AlertTriangle size={16} />
              <span>{loginError}</span>
            </div>
          )}

          <form onSubmit={handleLogin}>
            <div style={{ position: 'relative', marginBottom: '20px' }}>
              <input
                type={showPin ? 'text' : 'password'}
                placeholder="رمز المرور الإداري..."
                value={pinInput}
                onChange={(e) => setPinInput(e.target.value)}
                autoFocus
                style={{
                  width: '100%',
                  padding: '14px 44px 14px 16px',
                  borderRadius: '16px',
                  border: '1px solid var(--hairline, rgba(60,60,67,0.2))',
                  backgroundColor: 'var(--input-bg, #f2f2f7)',
                  color: 'var(--label-primary, #1c1c1e)',
                  fontSize: '1rem',
                  fontWeight: 700,
                  textAlign: 'center',
                  letterSpacing: '2px',
                  outline: 'none',
                }}
              />
              <button
                type="button"
                onClick={() => setShowPin(!showPin)}
                style={{
                  position: 'absolute',
                  left: '12px',
                  top: '50%',
                  transform: 'translateY(-50%)',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--label-tertiary, #8e8e93)',
                }}
              >
                {showPin ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>

            <button
              type="submit"
              disabled={loginLoading || !pinInput.trim()}
              className="btn-apple-download"
              style={{
                width: '100%',
                padding: '14px',
                borderRadius: '16px',
                fontSize: '0.98rem',
                fontWeight: 800,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                cursor: loginLoading ? 'wait' : 'pointer',
              }}
            >
              <Lock size={18} />
              <span>{loginLoading ? 'جارِ التحقق...' : 'تسجيل الدخول الآمن'}</span>
            </button>
          </form>
        </div>
      </div>
    );
  }

  // -------------------------------------------------------------
  // LOADING STATE
  // -------------------------------------------------------------
  if (isAuthenticated === null || !config) {
    return (
      <div style={{ minHeight: '60vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ textAlign: 'center', color: 'var(--label-secondary, #8e8e93)' }}>
          <RefreshCw size={28} className="animate-spin" style={{ margin: '0 auto 12px' }} />
          <p style={{ fontWeight: 600 }}>جارِ تحميل لوحة التحكم...</p>
        </div>
      </div>
    );
  }

  // -------------------------------------------------------------
  // AUTHENTICATED ADMIN DASHBOARD
  // -------------------------------------------------------------
  return (
    <div style={{ direction: 'rtl', padding: '24px 0 60px' }}>
      <div className="container" style={{ maxWidth: '1120px' }}>
        {/* Top Header Card */}
        <div
          style={{
            backgroundColor: 'var(--bg-card, #ffffff)',
            borderRadius: '24px',
            padding: '24px 28px',
            boxShadow: 'var(--shadow-subtle)',
            border: '1px solid var(--hairline)',
            marginBottom: '24px',
            display: 'flex',
            flexWrap: 'wrap',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '16px',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
            <div
              style={{
                width: '56px',
                height: '56px',
                borderRadius: '18px',
                backgroundColor: 'rgba(0, 122, 255, 0.1)',
                color: 'var(--apple-blue)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <Shield size={30} />
            </div>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <h1 style={{ fontSize: '1.45rem', fontWeight: 900, margin: 0 }}>
                  لوحة تحكم وتوزيع الفروع (VPN Control)
                </h1>
                <span
                  style={{
                    backgroundColor: 'rgba(52, 199, 89, 0.12)',
                    color: 'var(--apple-green)',
                    fontSize: '0.75rem',
                    fontWeight: 800,
                    padding: '4px 10px',
                    borderRadius: '999px',
                  }}
                >
                  متصل ومحمي
                </span>
              </div>
              <p style={{ fontSize: '0.85rem', color: 'var(--label-secondary)', margin: '4px 0 0' }}>
                إدارة أجهزة الفروع الـ 50، حظر التكدس على شبكة الـ VPN، وتبديل ملفات التثبيت فورياً.
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <button
              onClick={() => fetchStatus()}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '10px 16px',
                borderRadius: '14px',
                border: '1px solid var(--hairline)',
                backgroundColor: 'var(--bg-system)',
                color: 'var(--label-primary)',
                fontWeight: 700,
                fontSize: '0.86rem',
                cursor: 'pointer',
              }}
              title="تحديث البيانات"
            >
              <RefreshCw size={15} className={loadingStats ? 'animate-spin' : ''} />
              <span>تحديث</span>
            </button>

            <button
              onClick={handleLogout}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '10px 16px',
                borderRadius: '14px',
                border: 'none',
                backgroundColor: 'rgba(255, 59, 48, 0.1)',
                color: 'var(--apple-red)',
                fontWeight: 700,
                fontSize: '0.86rem',
                cursor: 'pointer',
              }}
            >
              <LogOut size={15} />
              <span>تسجيل الخروج</span>
            </button>
          </div>
        </div>

        {/* Global Save Alert */}
        {saveStatus && (
          <div
            style={{
              backgroundColor: saveStatus.isError ? 'rgba(255, 59, 48, 0.12)' : 'rgba(52, 199, 89, 0.12)',
              color: saveStatus.isError ? 'var(--apple-red)' : 'var(--apple-green)',
              borderRadius: '16px',
              padding: '14px 20px',
              marginBottom: '20px',
              fontWeight: 700,
              fontSize: '0.92rem',
              display: 'flex',
              alignItems: 'center',
              gap: '10px',
              boxShadow: 'var(--shadow-subtle)',
            }}
          >
            {saveStatus.isError ? <AlertTriangle size={20} /> : <CheckCircle2 size={20} />}
            <span>{saveStatus.message}</span>
          </div>
        )}

        {/* Quick Emergency Controls Banner */}
        <div
          style={{
            backgroundColor: config.globalDownloadsEnabled ? 'var(--bg-card)' : 'rgba(255, 59, 48, 0.08)',
            border: `1px solid ${config.globalDownloadsEnabled ? 'var(--hairline)' : 'rgba(255, 59, 48, 0.3)'}`,
            borderRadius: '20px',
            padding: '18px 24px',
            marginBottom: '24px',
            display: 'flex',
            flexWrap: 'wrap',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '16px',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
            <div
              style={{
                width: '42px',
                height: '42px',
                borderRadius: '12px',
                backgroundColor: config.globalDownloadsEnabled ? 'rgba(52, 199, 89, 0.12)' : 'rgba(255, 59, 48, 0.15)',
                color: config.globalDownloadsEnabled ? 'var(--apple-green)' : 'var(--apple-red)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <Power size={22} />
            </div>
            <div>
              <div style={{ fontWeight: 800, fontSize: '1rem' }}>
                مفتاح الطوارئ العام للتحميلات (Global Download Switch)
              </div>
              <div style={{ fontSize: '0.82rem', color: 'var(--label-secondary)' }}>
                {config.globalDownloadsEnabled
                  ? 'التحميلات مسموحة حالياً في الفروع وتخضع لسياسات منع التكدس والسرعة المحددة.'
                  : 'تم إيقاف كافة التحميلات في جميع الـ 50 فرعاً! لا يمكن لأي جهاز التحميل الآن.'}
              </div>
            </div>
          </div>

          <button
            onClick={() => handleSaveConfig({ globalDownloadsEnabled: !config.globalDownloadsEnabled })}
            style={{
              backgroundColor: config.globalDownloadsEnabled ? 'var(--apple-red)' : 'var(--apple-green)',
              color: '#ffffff',
              border: 'none',
              borderRadius: '14px',
              padding: '10px 22px',
              fontWeight: 800,
              fontSize: '0.88rem',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
            }}
          >
            <Power size={16} />
            <span>
              {config.globalDownloadsEnabled ? 'إيقاف التحميلات فوراً للطوارئ' : 'تشغيل وسماح التحميلات'}
            </span>
          </button>
        </div>

        {/* Tab Navigation Navigation Bar */}
        <div
          style={{
            display: 'flex',
            gap: '8px',
            overflowX: 'auto',
            paddingBottom: '8px',
            marginBottom: '20px',
          }}
        >
          {[
            { id: 'live', label: 'المراقبة الحية والتحميلات النشطة', icon: Activity, badge: activeDownloads.length },
            { id: 'toggles', label: 'مفاتيح التحكم والإيقاف', icon: Sliders },
            { id: 'vpn', label: 'سياسات الـ VPN والتكدس', icon: Network },
            { id: 'branches', label: 'تسمية الفروع الـ 50', icon: Server },
            { id: 'files', label: 'استبدال ورفع الملفات', icon: UploadCloud },
            { id: 'security', label: 'رمز الدخول السري', icon: Lock },
          ].map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  padding: '12px 18px',
                  borderRadius: '16px',
                  border: 'none',
                  backgroundColor: isActive ? 'var(--apple-blue)' : 'var(--bg-card)',
                  color: isActive ? '#ffffff' : 'var(--label-primary)',
                  fontWeight: 800,
                  fontSize: '0.88rem',
                  cursor: 'pointer',
                  boxShadow: isActive ? '0 4px 12px rgba(0, 122, 255, 0.3)' : 'var(--shadow-subtle)',
                  whiteSpace: 'nowrap',
                  transition: 'all 0.15s ease',
                }}
              >
                <Icon size={16} />
                <span>{tab.label}</span>
                {typeof tab.badge === 'number' && tab.badge > 0 && (
                  <span
                    style={{
                      backgroundColor: isActive ? 'rgba(255,255,255,0.3)' : 'var(--apple-orange)',
                      color: '#ffffff',
                      fontSize: '0.72rem',
                      borderRadius: '999px',
                      padding: '2px 7px',
                      fontWeight: 800,
                    }}
                  >
                    {tab.badge}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {/* ------------------------------------------------------------- */}
        {/* TAB 1: LIVE MONITOR */}
        {/* ------------------------------------------------------------- */}
        {activeTab === 'live' && (
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              borderRadius: '24px',
              padding: '28px',
              boxShadow: 'var(--shadow-subtle)',
              border: '1px solid var(--hairline)',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <div>
                <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 4px' }}>
                  الأجهزة التي تقوم بالتحميل حالياً في الفروع ({activeDownloads.length})
                </h3>
                <p style={{ fontSize: '0.84rem', color: 'var(--label-secondary)', margin: 0 }}>
                  تحديث فوري كل 4 ثوانٍ. يتم حظر أي جهاز إضافي في نفس الفرع تلقائياً لحماية اتصال الـ VPN.
                </p>
              </div>

              <div style={{ fontSize: '0.8rem', color: 'var(--label-tertiary)', fontWeight: 600 }}>
                السرعة المحددة للفرع: <strong>{config.vpnPolicy.speedLimitKBps ? `${(config.vpnPolicy.speedLimitKBps / 1024).toFixed(1)} MB/s` : 'مفتوحة'}</strong>
              </div>
            </div>

            {activeDownloads.length === 0 ? (
              <div
                style={{
                  textAlign: 'center',
                  padding: '48px 20px',
                  borderRadius: '18px',
                  backgroundColor: 'var(--bg-system)',
                  color: 'var(--label-secondary)',
                }}
              >
                <CheckCircle2 size={40} style={{ color: 'var(--apple-green)', margin: '0 auto 12px' }} />
                <h4 style={{ fontSize: '1.05rem', fontWeight: 800, margin: '0 0 4px' }}>
                  شبكة الـ VPN خالية ومستقرة تماماً
                </h4>
                <p style={{ fontSize: '0.85rem', margin: 0 }}>
                  لا يوجد أي جهاز يقوم بالتحميل في أي فرع في هذه اللحظة.
                </p>
              </div>
            ) : (
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'right' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--hairline)', color: 'var(--label-secondary)', fontSize: '0.82rem' }}>
                      <th style={{ padding: '12px 14px' }}>الفرع المكتشف</th>
                      <th style={{ padding: '12px 14px' }}>عنوان الجهاز (IP)</th>
                      <th style={{ padding: '12px 14px' }}>الملف</th>
                      <th style={{ padding: '12px 14px' }}>الحجم المنقول</th>
                      <th style={{ padding: '12px 14px' }}>الحالة والسرعة</th>
                      <th style={{ padding: '12px 14px', textAlign: 'center' }}>إجراء إداري</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activeDownloads.map((s) => {
                      const percent = s.totalBytes > 0 ? Math.min(100, Math.round((s.bytesTransferred / s.totalBytes) * 100)) : 0;
                      return (
                        <tr key={s.id} style={{ borderBottom: '1px solid var(--hairline-subtle)', fontSize: '0.88rem' }}>
                          <td style={{ padding: '14px', fontWeight: 700 }}>
                            🏢 {s.branchName} <br />
                            <span style={{ fontSize: '0.75rem', color: 'var(--label-tertiary)', fontWeight: 500 }}>
                              {s.subnet}
                            </span>
                          </td>
                          <td style={{ padding: '14px', fontWeight: 700, direction: 'ltr', textAlign: 'right' }}>
                            💻 {s.ip}
                          </td>
                          <td style={{ padding: '14px' }}>
                            {s.fileKey === 'windows' ? '💻 نسخة الكمبيوتر' : '📱 نسخة الموبايل'} <br />
                            <span style={{ fontSize: '0.75rem', color: 'var(--label-tertiary)' }}>{s.fileName}</span>
                          </td>
                          <td style={{ padding: '14px', fontWeight: 700 }}>
                            {formatBytes(s.bytesTransferred)} / {formatBytes(s.totalBytes)} ({percent}%)
                            {/* Mini progress bar */}
                            <div
                              style={{
                                height: '6px',
                                width: '100%',
                                backgroundColor: 'var(--hairline)',
                                borderRadius: '3px',
                                marginTop: '6px',
                                overflow: 'hidden',
                              }}
                            >
                              <div
                                style={{
                                  height: '100%',
                                  width: `${percent}%`,
                                  backgroundColor: 'var(--apple-blue)',
                                  borderRadius: '3px',
                                  transition: 'width 0.3s ease',
                                }}
                              />
                            </div>
                          </td>
                          <td style={{ padding: '14px' }}>
                            <span
                              style={{
                                display: 'inline-flex',
                                alignItems: 'center',
                                gap: '4px',
                                color: 'var(--apple-green)',
                                fontWeight: 700,
                                fontSize: '0.8rem',
                              }}
                            >
                              <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: 'var(--apple-green)' }} />
                              نشط ({s.speedLimitKBps ? `${(s.speedLimitKBps / 1024).toFixed(1)} MB/s` : 'Max'})
                            </span>
                          </td>
                          <td style={{ padding: '14px', textAlign: 'center' }}>
                            <button
                              onClick={() => handleKillSession(s.id)}
                              style={{
                                backgroundColor: 'rgba(255, 59, 48, 0.12)',
                                color: 'var(--apple-red)',
                                border: 'none',
                                borderRadius: '10px',
                                padding: '6px 14px',
                                fontSize: '0.78rem',
                                fontWeight: 800,
                                cursor: 'pointer',
                              }}
                              title="إلغاء التحميل وفك قفل الفرع فوراً"
                            >
                              إنهاء وفك القفل
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* ------------------------------------------------------------- */}
        {/* TAB 2: TOGGLES & MAINTENANCE */}
        {/* ------------------------------------------------------------- */}
        {activeTab === 'toggles' && (
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              borderRadius: '24px',
              padding: '28px',
              boxShadow: 'var(--shadow-subtle)',
              border: '1px solid var(--hairline)',
            }}
          >
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 6px' }}>
              التحكم في إتاحة وإيقاف التحميلات
            </h3>
            <p style={{ fontSize: '0.85rem', color: 'var(--label-secondary)', margin: '0 0 24px' }}>
              يمكنك إيقاف تحميل نسخة الكمبيوتر أو الموبايل بشكل مستقل، أو إظهار رسالة صيانة للموظفين.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '18px', marginBottom: '28px' }}>
              {/* WINDOWS TOGGLE CARD */}
              <div
                style={{
                  padding: '20px',
                  borderRadius: '18px',
                  backgroundColor: 'var(--bg-system)',
                  border: '1px solid var(--hairline)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div
                    style={{
                      width: '46px',
                      height: '46px',
                      borderRadius: '14px',
                      backgroundColor: 'rgba(0, 122, 255, 0.12)',
                      color: 'var(--apple-blue)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    <Laptop size={24} />
                  </div>
                  <div>
                    <h4 style={{ margin: '0 0 2px', fontSize: '1rem', fontWeight: 800 }}>تحميل نسخة الكمبيوتر (Windows)</h4>
                    <span style={{ fontSize: '0.78rem', color: config.windows.enabled ? 'var(--apple-green)' : 'var(--apple-red)', fontWeight: 700 }}>
                      {config.windows.enabled ? '● التحميل متاح حالياً' : '○ التحميل متوقف مؤقتاً'}
                    </span>
                  </div>
                </div>

                <button
                  onClick={() =>
                    handleSaveConfig({
                      windows: { ...config.windows, enabled: !config.windows.enabled },
                    })
                  }
                  style={{
                    backgroundColor: config.windows.enabled ? 'var(--apple-blue)' : 'var(--hairline)',
                    color: '#ffffff',
                    border: 'none',
                    borderRadius: '12px',
                    padding: '8px 18px',
                    fontWeight: 800,
                    fontSize: '0.82rem',
                    cursor: 'pointer',
                  }}
                >
                  {config.windows.enabled ? 'إيقاف التحميل' : 'تفعيل التحميل'}
                </button>
              </div>

              {/* MOBILE TOGGLE CARD */}
              <div
                style={{
                  padding: '20px',
                  borderRadius: '18px',
                  backgroundColor: 'var(--bg-system)',
                  border: '1px solid var(--hairline)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div
                    style={{
                      width: '46px',
                      height: '46px',
                      borderRadius: '14px',
                      backgroundColor: 'rgba(52, 199, 89, 0.12)',
                      color: 'var(--apple-green)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    <Smartphone size={24} />
                  </div>
                  <div>
                    <h4 style={{ margin: '0 0 2px', fontSize: '1rem', fontWeight: 800 }}>تحميل نسخة الموبايل (Android APK)</h4>
                    <span style={{ fontSize: '0.78rem', color: config.mobile.enabled ? 'var(--apple-green)' : 'var(--apple-red)', fontWeight: 700 }}>
                      {config.mobile.enabled ? '● التحميل متاح حالياً' : '○ التحميل متوقف مؤقتاً'}
                    </span>
                  </div>
                </div>

                <button
                  onClick={() =>
                    handleSaveConfig({
                      mobile: { ...config.mobile, enabled: !config.mobile.enabled },
                    })
                  }
                  style={{
                    backgroundColor: config.mobile.enabled ? 'var(--apple-green)' : 'var(--hairline)',
                    color: '#ffffff',
                    border: 'none',
                    borderRadius: '12px',
                    padding: '8px 18px',
                    fontWeight: 800,
                    fontSize: '0.82rem',
                    cursor: 'pointer',
                  }}
                >
                  {config.mobile.enabled ? 'إيقاف التحميل' : 'تفعيل التحميل'}
                </button>
              </div>
            </div>

            {/* Maintenance Message */}
            <div style={{ borderTop: '1px solid var(--hairline)', paddingTop: '22px' }}>
              <label style={{ display: 'block', fontWeight: 800, fontSize: '0.94rem', marginBottom: '8px' }}>
                رسالة التنبيه والصيانة للموظفين (اختياري)
              </label>
              <p style={{ fontSize: '0.82rem', color: 'var(--label-secondary)', margin: '0 0 10px' }}>
                تظهر هذه الرسالة في شريط الإعلانات أعلى الموقع أو عند محاولة أي شخص التحميل أثناء الإيقاف.
              </p>
              <textarea
                rows={3}
                value={config.maintenanceMessage || ''}
                onChange={(e) => setConfig({ ...config, maintenanceMessage: e.target.value })}
                placeholder="مثال: يرجى العلم أنه جارٍ تحديث خوادم المنظومة الآن وسيتم فتح التحميلات الساعة 4 عصراً..."
                style={{
                  width: '100%',
                  padding: '14px',
                  borderRadius: '16px',
                  border: '1px solid var(--hairline)',
                  backgroundColor: 'var(--input-bg)',
                  color: 'var(--label-primary)',
                  fontSize: '0.9rem',
                  outline: 'none',
                  resize: 'vertical',
                  marginBottom: '14px',
                }}
              />
              <button
                onClick={() => handleSaveConfig({ maintenanceMessage: config.maintenanceMessage })}
                className="btn-apple-download"
                style={{ padding: '10px 24px', fontSize: '0.88rem' }}
              >
                <Save size={16} />
                <span>حفظ رسالة الصيانة</span>
              </button>
            </div>
          </div>
        )}

        {/* ------------------------------------------------------------- */}
        {/* TAB 3: VPN & CONCURRENCY POLICIES */}
        {/* ------------------------------------------------------------- */}
        {activeTab === 'vpn' && (
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              borderRadius: '24px',
              padding: '28px',
              boxShadow: 'var(--shadow-subtle)',
              border: '1px solid var(--hairline)',
            }}
          >
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 6px' }}>
              سياسات شبكة الـ VPN ومنع التكدس بالفروع
            </h3>
            <p style={{ fontSize: '0.85rem', color: 'var(--label-secondary)', margin: '0 0 24px' }}>
              هذه الإعدادات تحمي خط الـ VPN في كل فرع من السقوط أو البطء عند محاولة الموظفين التحميل في وقت واحد.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '20px', marginBottom: '28px' }}>
              {/* Max Per Branch */}
              <div style={{ backgroundColor: 'var(--bg-system)', padding: '18px', borderRadius: '16px' }}>
                <label style={{ display: 'block', fontWeight: 800, fontSize: '0.9rem', marginBottom: '6px' }}>
                  أقصى عدد تحميلات متزامنة للفرع الواحد
                </label>
                <span style={{ fontSize: '0.78rem', color: 'var(--label-secondary)', display: 'block', marginBottom: '12px' }}>
                  إذا كان 1، فلن يستطيع أي جهاز في الفرع التحميل إلا بعد انتهاء الجهاز الأول.
                </span>
                <select
                  value={config.vpnPolicy.maxConcurrentPerBranch}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      vpnPolicy: { ...config.vpnPolicy, maxConcurrentPerBranch: parseInt(e.target.value, 10) },
                    })
                  }
                  style={{
                    width: '100%',
                    padding: '10px 14px',
                    borderRadius: '12px',
                    border: '1px solid var(--hairline)',
                    backgroundColor: 'var(--bg-card)',
                    color: 'var(--label-primary)',
                    fontWeight: 700,
                  }}
                >
                  <option value={1}>1 جهاز فقط في نفس الوقت (الموصى به للـ VPN)</option>
                  <option value={2}>2 جهازين في نفس الوقت</option>
                  <option value={3}>3 أجهزة في نفس الوقت</option>
                  <option value={5}>5 أجهزة في نفس الوقت</option>
                  <option value={999}>مفتوح بدون تحديد (غير موصى به)</option>
                </select>
              </div>

              {/* Speed Limit */}
              <div style={{ backgroundColor: 'var(--bg-system)', padding: '18px', borderRadius: '16px' }}>
                <label style={{ display: 'block', fontWeight: 800, fontSize: '0.9rem', marginBottom: '6px' }}>
                  الحد الأقصى لسرعة التحميل (Bandwidth Cap)
                </label>
                <span style={{ fontSize: '0.78rem', color: 'var(--label-secondary)', display: 'block', marginBottom: '12px' }}>
                  تحديد سرعة التحميل يمنع استهلاك كامل سعة نفق الـ VPN ويترك سرعة كافية لبرامج الشركة.
                </span>
                <select
                  value={config.vpnPolicy.speedLimitKBps}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      vpnPolicy: { ...config.vpnPolicy, speedLimitKBps: parseInt(e.target.value, 10) },
                    })
                  }
                  style={{
                    width: '100%',
                    padding: '10px 14px',
                    borderRadius: '12px',
                    border: '1px solid var(--hairline)',
                    backgroundColor: 'var(--bg-card)',
                    color: 'var(--label-primary)',
                    fontWeight: 700,
                  }}
                >
                  <option value={1024}>1.0 MB/s (أقصى حماية لسرعة الـ VPN)</option>
                  <option value={1536}>1.5 MB/s (متوازن جداً)</option>
                  <option value={2048}>2.0 MB/s (الموصى به - ينتهي في دقيقة تقريباً)</option>
                  <option value={3072}>3.0 MB/s (سريع)</option>
                  <option value={5120}>5.0 MB/s (فائق السرعة)</option>
                  <option value={0}>بدون تحديد سرعة (سرعة الخط القصوى)</option>
                </select>
              </div>

              {/* Subnet Mask */}
              <div style={{ backgroundColor: 'var(--bg-system)', padding: '18px', borderRadius: '16px' }}>
                <label style={{ display: 'block', fontWeight: 800, fontSize: '0.9rem', marginBottom: '6px' }}>
                  قناع تصنيف الفرع (Subnet Mask)
                </label>
                <span style={{ fontSize: '0.78rem', color: 'var(--label-secondary)', display: 'block', marginBottom: '12px' }}>
                  كيف يتعرف النظام على أن الجهازين في نفس الفرع؟
                </span>
                <select
                  value={config.vpnPolicy.subnetMask}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      vpnPolicy: { ...config.vpnPolicy, subnetMask: e.target.value },
                    })
                  }
                  style={{
                    width: '100%',
                    padding: '10px 14px',
                    borderRadius: '12px',
                    border: '1px solid var(--hairline)',
                    backgroundColor: 'var(--bg-card)',
                    color: 'var(--label-primary)',
                    fontWeight: 700,
                  }}
                >
                  <option value="24">/24 (مثال: 192.168.10.x كلها فرع واحد - القياسي)</option>
                  <option value="16">/16 (مثال: 192.168.x.x)</option>
                </select>
              </div>
            </div>

            {/* Whitelisted Subnets & IPs */}
            <div style={{ borderTop: '1px solid var(--hairline)', paddingTop: '22px', marginBottom: '22px' }}>
              <h4 style={{ fontWeight: 800, fontSize: '1rem', margin: '0 0 6px' }}>
                الفروع المستثناة من قيود التكدس (Whitelisted Subnets / HQ)
              </h4>
              <p style={{ fontSize: '0.82rem', color: 'var(--label-secondary)', margin: '0 0 14px' }}>
                الفروع المضافة هنا (مثل الإدارة العامة أو قسم الـ IT) تستطيع التحميل بأي عدد من الأجهزة المتزامنة بدون أي انتظار.
              </p>

              <div style={{ display: 'flex', gap: '10px', marginBottom: '16px', maxWidth: '480px' }}>
                <input
                  type="text"
                  placeholder="مثال: 192.168.1.0/24 أو 10.0.0.0/24..."
                  value={newWhitelistSubnet}
                  onChange={(e) => setNewWhitelistSubnet(e.target.value)}
                  style={{
                    flex: 1,
                    padding: '10px 14px',
                    borderRadius: '12px',
                    border: '1px solid var(--hairline)',
                    backgroundColor: 'var(--input-bg)',
                    color: 'var(--label-primary)',
                    fontSize: '0.88rem',
                    outline: 'none',
                    direction: 'ltr',
                    textAlign: 'left',
                  }}
                />
                <button
                  onClick={() => {
                    if (!newWhitelistSubnet.trim()) return;
                    const list = config.vpnPolicy.whitelistedSubnets || [];
                    if (!list.includes(newWhitelistSubnet.trim())) {
                      const updated = {
                        ...config,
                        vpnPolicy: { ...config.vpnPolicy, whitelistedSubnets: [...list, newWhitelistSubnet.trim()] },
                      };
                      setConfig(updated);
                      handleSaveConfig(updated);
                      setNewWhitelistSubnet('');
                    }
                  }}
                  className="btn-apple-download"
                  style={{ padding: '10px 18px', fontSize: '0.84rem' }}
                >
                  <Plus size={16} />
                  <span>إضافة استثناء</span>
                </button>
              </div>

              {/* Subnet tags */}
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
                {(config.vpnPolicy.whitelistedSubnets || []).map((sub: string) => (
                  <span
                    key={sub}
                    style={{
                      backgroundColor: 'var(--bg-system)',
                      border: '1px solid var(--hairline)',
                      padding: '6px 12px',
                      borderRadius: '10px',
                      fontSize: '0.82rem',
                      fontWeight: 700,
                      display: 'flex',
                      alignItems: 'center',
                      gap: '8px',
                      direction: 'ltr',
                    }}
                  >
                    <span>{sub}</span>
                    <button
                      onClick={() => {
                        const updated = {
                          ...config,
                          vpnPolicy: {
                            ...config.vpnPolicy,
                            whitelistedSubnets: config.vpnPolicy.whitelistedSubnets.filter((s: string) => s !== sub),
                          },
                        };
                        setConfig(updated);
                        handleSaveConfig(updated);
                      }}
                      style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--apple-red)', padding: 0 }}
                      title="حذف الاستثناء"
                    >
                      <Trash2 size={14} />
                    </button>
                  </span>
                ))}
              </div>
            </div>

            <button
              onClick={() => handleSaveConfig({ vpnPolicy: config.vpnPolicy })}
              className="btn-apple-download"
              style={{ padding: '12px 28px', fontSize: '0.9rem' }}
            >
              <Save size={16} />
              <span>حفظ سياسات الـ VPN بالكامل</span>
            </button>
          </div>
        )}

        {/* ------------------------------------------------------------- */}
        {/* TAB 4: BRANCH NAMES MAPPING */}
        {/* ------------------------------------------------------------- */}
        {activeTab === 'branches' && (
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              borderRadius: '24px',
              padding: '28px',
              boxShadow: 'var(--shadow-subtle)',
              border: '1px solid var(--hairline)',
            }}
          >
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 6px' }}>
              تسمية الفروع الـ 50 (Branch Subnets Mapping)
            </h3>
            <p style={{ fontSize: '0.85rem', color: 'var(--label-secondary)', margin: '0 0 20px' }}>
              اربط كل شبكة فرعية (Subnet) باسم الفرع المقابل لها، لتظهر الأسماء العربية واضحة في المراقبة الحية والتحذيرات بدلاً من مجرد أرقام IP.
            </p>

            {/* Add Branch */}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', marginBottom: '24px', backgroundColor: 'var(--bg-system)', padding: '16px', borderRadius: '16px' }}>
              <div style={{ flex: '1 1 200px' }}>
                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 700, marginBottom: '4px' }}>شبكة الفرع (Subnet)</label>
                <input
                  type="text"
                  placeholder="مثال: 192.168.10.0/24"
                  value={newBranchSubnet}
                  onChange={(e) => setNewBranchSubnet(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '10px 12px',
                    borderRadius: '10px',
                    border: '1px solid var(--hairline)',
                    backgroundColor: 'var(--bg-card)',
                    direction: 'ltr',
                    textAlign: 'left',
                  }}
                />
              </div>

              <div style={{ flex: '1 1 240px' }}>
                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 700, marginBottom: '4px' }}>اسم الفرع الرسمي</label>
                <input
                  type="text"
                  placeholder="مثال: فرع مدينة نصر، فرع الإسكندرية..."
                  value={newBranchName}
                  onChange={(e) => setNewBranchName(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '10px 12px',
                    borderRadius: '10px',
                    border: '1px solid var(--hairline)',
                    backgroundColor: 'var(--bg-card)',
                  }}
                />
              </div>

              <div style={{ display: 'flex', alignItems: 'flex-end' }}>
                <button
                  onClick={() => {
                    if (!newBranchSubnet.trim() || !newBranchName.trim()) return;
                    const updated = {
                      ...config,
                      branches: {
                        ...config.branches,
                        [newBranchSubnet.trim()]: newBranchName.trim(),
                      },
                    };
                    setConfig(updated);
                    handleSaveConfig(updated);
                    setNewBranchSubnet('');
                    setNewBranchName('');
                  }}
                  className="btn-apple-download"
                  style={{ padding: '10px 20px', fontSize: '0.84rem' }}
                >
                  <Plus size={16} />
                  <span>إضافة / تحديث الفرع</span>
                </button>
              </div>
            </div>

            {/* List of Mapped Branches */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '12px' }}>
              {Object.entries(config.branches || {}).map(([subnet, name]) => (
                <div
                  key={subnet}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '12px 16px',
                    borderRadius: '14px',
                    backgroundColor: 'var(--bg-system)',
                    border: '1px solid var(--hairline-subtle)',
                  }}
                >
                  <div>
                    <div style={{ fontWeight: 800, fontSize: '0.92rem' }}>🏢 {String(name)}</div>
                    <div style={{ fontSize: '0.78rem', color: 'var(--label-secondary)', direction: 'ltr', textAlign: 'right' }}>
                      {subnet}
                    </div>
                  </div>

                  <button
                    onClick={() => {
                      const copy = { ...config.branches };
                      delete copy[subnet];
                      const updated = { ...config, branches: copy };
                      setConfig(updated);
                      handleSaveConfig(updated);
                    }}
                    style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--apple-red)' }}
                    title="حذف الفرع"
                  >
                    <Trash2 size={16} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ------------------------------------------------------------- */}
        {/* TAB 5: FILE REPLACEMENT & VERSIONS */}
        {/* ------------------------------------------------------------- */}
        {activeTab === 'files' && (
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              borderRadius: '24px',
              padding: '28px',
              boxShadow: 'var(--shadow-subtle)',
              border: '1px solid var(--hairline)',
            }}
          >
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 6px' }}>
              استبدال ورفع ملفات التحميل الجديدة
            </h3>
            <p style={{ fontSize: '0.85rem', color: 'var(--label-secondary)', margin: '0 0 24px' }}>
              ارفع ملف التثبيت الجديد (.exe أو .apk) مباشرة من متصفحك. يتم استبدال الملف فورياً وتحديث رقم الإصدار وحجم الملف التلقائي في الموقع.
            </p>

            {uploadMessage && (
              <div
                style={{
                  backgroundColor: 'rgba(52, 199, 89, 0.12)',
                  color: 'var(--apple-green)',
                  borderRadius: '14px',
                  padding: '12px 18px',
                  marginBottom: '20px',
                  fontWeight: 700,
                  fontSize: '0.9rem',
                }}
              >
                ✅ {uploadMessage}
              </div>
            )}

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(340px, 1fr))', gap: '24px' }}>
              {/* WINDOWS EXE UPLOADER */}
              <div
                style={{
                  backgroundColor: 'var(--bg-system)',
                  borderRadius: '20px',
                  padding: '22px',
                  border: '1px solid var(--hairline)',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '14px' }}>
                  <Laptop size={24} style={{ color: 'var(--apple-blue)' }} />
                  <h4 style={{ margin: 0, fontWeight: 800, fontSize: '1.05rem' }}>
                    تحديث برنامج الكمبيوتر (Windows EXE)
                  </h4>
                </div>

                <div style={{ fontSize: '0.8rem', color: 'var(--label-secondary)', marginBottom: '14px', lineHeight: 1.6 }}>
                  الملف النشط حالياً: <strong>{config.windows.fileName}</strong> <br />
                  الحجم: <strong>{config.windows.fileSize}</strong> | الإصدار: <strong>{config.windows.version}</strong>
                </div>

                <div style={{ marginBottom: '14px' }}>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, marginBottom: '6px' }}>
                    رقم الإصدار الجديد (Version)
                  </label>
                  <input
                    type="text"
                    value={windowsVersion}
                    onChange={(e) => setWindowsVersion(e.target.value)}
                    placeholder="مثال: 1.1.16"
                    style={{
                      width: '100%',
                      padding: '10px 12px',
                      borderRadius: '12px',
                      border: '1px solid var(--hairline)',
                      backgroundColor: 'var(--bg-card)',
                      color: 'var(--label-primary)',
                      fontWeight: 700,
                    }}
                  />
                </div>

                <div style={{ marginBottom: '16px' }}>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, marginBottom: '6px' }}>
                    اختر ملف .exe الجديد من جهازك
                  </label>
                  <input
                    type="file"
                    accept=".exe"
                    onChange={(e) => setWindowsFile(e.target.files?.[0] || null)}
                    style={{
                      width: '100%',
                      padding: '8px',
                      borderRadius: '10px',
                      fontSize: '0.85rem',
                    }}
                  />
                </div>

                <button
                  onClick={() => handleFileUpload('windows')}
                  disabled={uploadingWindows || !windowsFile}
                  className="btn-apple-download"
                  style={{
                    width: '100%',
                    padding: '12px',
                    fontSize: '0.88rem',
                    opacity: uploadingWindows || !windowsFile ? 0.6 : 1,
                  }}
                >
                  <UploadCloud size={16} />
                  <span>{uploadingWindows ? 'جارِ رفع واستبدال الملف...' : 'رفع واستبدال نسخة الكمبيوتر'}</span>
                </button>
              </div>

              {/* MOBILE APK UPLOADER */}
              <div
                style={{
                  backgroundColor: 'var(--bg-system)',
                  borderRadius: '20px',
                  padding: '22px',
                  border: '1px solid var(--hairline)',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '14px' }}>
                  <Smartphone size={24} style={{ color: 'var(--apple-green)' }} />
                  <h4 style={{ margin: 0, fontWeight: 800, fontSize: '1.05rem' }}>
                    تحديث تطبيق الموبايل (Android APK)
                  </h4>
                </div>

                <div style={{ fontSize: '0.8rem', color: 'var(--label-secondary)', marginBottom: '14px', lineHeight: 1.6 }}>
                  الملف النشط حالياً: <strong>{config.mobile.fileName}</strong> <br />
                  الحجم: <strong>{config.mobile.fileSize}</strong> | الإصدار: <strong>{config.mobile.version}</strong>
                </div>

                <div style={{ marginBottom: '14px' }}>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, marginBottom: '6px' }}>
                    رقم الإصدار الجديد (Version)
                  </label>
                  <input
                    type="text"
                    value={mobileVersion}
                    onChange={(e) => setMobileVersion(e.target.value)}
                    placeholder="مثال: 1.0.3"
                    style={{
                      width: '100%',
                      padding: '10px 12px',
                      borderRadius: '12px',
                      border: '1px solid var(--hairline)',
                      backgroundColor: 'var(--bg-card)',
                      color: 'var(--label-primary)',
                      fontWeight: 700,
                    }}
                  />
                </div>

                <div style={{ marginBottom: '16px' }}>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, marginBottom: '6px' }}>
                    اختر ملف .apk الجديد من جهازك
                  </label>
                  <input
                    type="file"
                    accept=".apk"
                    onChange={(e) => setMobileFile(e.target.files?.[0] || null)}
                    style={{
                      width: '100%',
                      padding: '8px',
                      borderRadius: '10px',
                      fontSize: '0.85rem',
                    }}
                  />
                </div>

                <button
                  onClick={() => handleFileUpload('mobile')}
                  disabled={uploadingMobile || !mobileFile}
                  className="btn-apple-download"
                  style={{
                    width: '100%',
                    padding: '12px',
                    fontSize: '0.88rem',
                    backgroundColor: 'var(--apple-green)',
                    opacity: uploadingMobile || !mobileFile ? 0.6 : 1,
                  }}
                >
                  <UploadCloud size={16} />
                  <span>{uploadingMobile ? 'جارِ رفع واستبدال الملف...' : 'رفع واستبدال نسخة الموبايل'}</span>
                </button>
              </div>
            </div>
          </div>
        )}

        {/* ------------------------------------------------------------- */}
        {/* TAB 6: SECURITY & PIN */}
        {/* ------------------------------------------------------------- */}
        {activeTab === 'security' && (
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              borderRadius: '24px',
              padding: '28px',
              boxShadow: 'var(--shadow-subtle)',
              border: '1px solid var(--hairline)',
              maxWidth: '560px',
            }}
          >
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 6px' }}>
              تغيير رمز الدخول السري (Admin PIN)
            </h3>
            <p style={{ fontSize: '0.85rem', color: 'var(--label-secondary)', margin: '0 0 20px' }}>
              احرص على استخدام رمز مرور قوي لا يعرفه إلا المسؤول المعتمد عن البوابة.
            </p>

            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'block', fontSize: '0.84rem', fontWeight: 700, marginBottom: '6px' }}>
                رمز المرور الجديد (New PIN)
              </label>
              <input
                type="password"
                value={newPin}
                onChange={(e) => setNewPin(e.target.value)}
                placeholder="أدخل الرمز الجديد..."
                style={{
                  width: '100%',
                  padding: '12px 14px',
                  borderRadius: '12px',
                  border: '1px solid var(--hairline)',
                  backgroundColor: 'var(--input-bg)',
                  fontSize: '0.95rem',
                }}
              />
            </div>

            <div style={{ marginBottom: '22px' }}>
              <label style={{ display: 'block', fontSize: '0.84rem', fontWeight: 700, marginBottom: '6px' }}>
                تأكيد رمز المرور الجديد
              </label>
              <input
                type="password"
                value={confirmPin}
                onChange={(e) => setConfirmPin(e.target.value)}
                placeholder="أعد إدخال الرمز للتأكيد..."
                style={{
                  width: '100%',
                  padding: '12px 14px',
                  borderRadius: '12px',
                  border: '1px solid var(--hairline)',
                  backgroundColor: 'var(--input-bg)',
                  fontSize: '0.95rem',
                }}
              />
            </div>

            <button
              onClick={() => {
                if (!newPin.trim()) {
                  alert('الرمز الجديد لا يمكن أن يكون فارغاً.');
                  return;
                }
                if (newPin !== confirmPin) {
                  alert('رمز المرور وتأكيده غير متطابقين!');
                  return;
                }
                handleSaveConfig({ adminPin: newPin.trim() });
                setNewPin('');
                setConfirmPin('');
              }}
              className="btn-apple-download"
              style={{ padding: '12px 28px', fontSize: '0.88rem' }}
            >
              <Save size={16} />
              <span>تحديث رمز المرور فوراً</span>
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
