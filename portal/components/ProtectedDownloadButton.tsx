'use client';

import React, { useState, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { Download, AlertTriangle, Loader2, ShieldAlert, X } from 'lucide-react';

interface ProtectedDownloadButtonProps {
  fileType: 'windows' | 'mobile';
  className?: string;
  children?: React.ReactNode;
  fallbackFileName?: string;
  style?: React.CSSProperties;
}

export default function ProtectedDownloadButton({
  fileType,
  className = 'btn-apple-download',
  children,
  fallbackFileName,
  style,
}: ProtectedDownloadButtonProps) {
  const [mounted, setMounted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [modalData, setModalData] = useState<{
    title: string;
    message: string;
    busyIp?: string;
    branchName?: string;
    clientIp?: string;
    isError?: boolean;
  } | null>(null);

  useEffect(() => {
    setMounted(true);
  }, []);

  const executeDownload = () => {
    const dlLink = document.createElement('a');
    dlLink.href = `/api/portal/download?file=${fileType}`;
    dlLink.setAttribute('download', '');
    document.body.appendChild(dlLink);
    dlLink.click();
    document.body.removeChild(dlLink);
  };

  const handleDownloadClick = async (e?: React.MouseEvent) => {
    if (e) e.preventDefault();
    if (loading) return;

    setLoading(true);

    try {
      const res = await fetch(`/api/portal/check-download?file=${fileType}`, {
        cache: 'no-store',
      });
      const data = await res.json();

      if (data.allowed) {
        setModalOpen(false);
        executeDownload();
      } else {
        setModalData({
          title:
            data.reason === 'branch_busy'
              ? 'تنبيه شبكة الفرع (VPN)'
              : data.reason === 'device_busy'
              ? 'جهازك يقوم بالتحميل حالياً'
              : 'التحميل متوقف مؤقتاً',
          message: data.message || 'تعذر بدء التحميل في الوقت الحالي.',
          busyIp: data.busyIp,
          branchName: data.branchName,
          clientIp: data.clientIp,
          isError: data.reason === 'maintenance' || data.reason === 'disabled',
        });
        setModalOpen(true);
      }
    } catch (err) {
      setModalData({
        title: 'تعذر الاتصال بالخادم',
        message: 'حدث خطأ في الاتصال بالسيرفر الداخلي. يرجى التحقق من اتصال الشبكة.',
        isError: true,
      });
      setModalOpen(true);
    } finally {
      setLoading(false);
    }
  };

  const handleRetryInModal = async () => {
    if (retrying) return;
    setRetrying(true);

    try {
      const res = await fetch(`/api/portal/check-download?file=${fileType}`, {
        cache: 'no-store',
      });
      const data = await res.json();

      if (data.allowed) {
        setModalOpen(false);
        executeDownload();
      } else {
        // Smoothly update modal content without closing or flickering
        setModalData({
          title:
            data.reason === 'branch_busy'
              ? 'تنبيه شبكة الفرع (VPN)'
              : data.reason === 'device_busy'
              ? 'جهازك يقوم بالتحميل حالياً'
              : 'التحميل متوقف مؤقتاً',
          message: data.message || 'تعذر بدء التحميل في الوقت الحالي.',
          busyIp: data.busyIp,
          branchName: data.branchName,
          clientIp: data.clientIp,
          isError: data.reason === 'maintenance' || data.reason === 'disabled',
        });
      }
    } catch (err) {
      // keep modal open
    } finally {
      setRetrying(false);
    }
  };

  // Apple-Style Protection Modal rendered via Portal to escape all card/transform/overflow contexts
  const modalPortal =
    mounted && modalOpen && modalData
      ? createPortal(
          <div
            style={{
              position: 'fixed',
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              width: '100vw',
              height: '100vh',
              zIndex: 999999,
              backgroundColor: 'rgba(0, 0, 0, 0.65)',
              backdropFilter: 'blur(8px)',
              WebkitBackdropFilter: 'blur(8px)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '16px',
              animation: 'fadeIn 0.18s ease-out',
            }}
            onClick={() => setModalOpen(false)}
          >
            <div
              style={{
                backgroundColor: 'var(--bg-card, #ffffff)',
                color: 'var(--label-primary, #1c1c1e)',
                borderRadius: '24px',
                maxWidth: '520px',
                width: '100%',
                padding: '28px',
                boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.35)',
                border: '1px solid var(--hairline, rgba(60, 60, 67, 0.12))',
                direction: 'rtl',
                textAlign: 'right',
                position: 'relative',
                animation: 'modalScaleIn 0.2s cubic-bezier(0.16, 1, 0.3, 1)',
              }}
              onClick={(e) => e.stopPropagation()}
            >
              {/* Close Button */}
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                style={{
                  position: 'absolute',
                  top: '20px',
                  left: '20px',
                  background: 'var(--bg-system, #f2f2f7)',
                  border: 'none',
                  borderRadius: '50%',
                  width: '32px',
                  height: '32px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  color: 'var(--label-secondary, #48484a)',
                  transition: 'background 0.15s ease',
                }}
                title="إغلاق"
              >
                <X size={18} />
              </button>

              {/* Icon Header */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '18px' }}>
                <div
                  style={{
                    width: '52px',
                    height: '52px',
                    borderRadius: '16px',
                    backgroundColor: modalData.isError
                      ? 'rgba(255, 59, 48, 0.12)'
                      : 'rgba(255, 149, 0, 0.12)',
                    color: modalData.isError
                      ? 'var(--apple-red, #ff3b30)'
                      : 'var(--apple-orange, #ff9500)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                  }}
                >
                  {modalData.isError ? <ShieldAlert size={28} /> : <AlertTriangle size={28} />}
                </div>
                <div>
                  <h3 style={{ fontSize: '1.25rem', fontWeight: 800, margin: 0 }}>
                    {modalData.title}
                  </h3>
                  <span style={{ fontSize: '0.82rem', color: 'var(--label-secondary, #8e8e93)' }}>
                    {modalData.isError
                      ? 'رسالة رسمية من إدارة الشبكة المركزية'
                      : 'نظام حماية اتصالات الفروع المشتركة (VPN Bandwidth Guard)'}
                  </span>
                </div>
              </div>

              {/* Message Body */}
              <p
                style={{
                  fontSize: '0.96rem',
                  lineHeight: 1.65,
                  color: 'var(--label-secondary, #48484a)',
                  margin: '0 0 20px',
                }}
              >
                {modalData.message}
              </p>

              {/* Branch and Network details badge if congestion */}
              {!modalData.isError && (modalData.branchName || modalData.clientIp || modalData.busyIp) && (
                <div
                  style={{
                    backgroundColor: 'var(--bg-system, #f2f2f7)',
                    borderRadius: '16px',
                    padding: '14px 16px',
                    marginBottom: '22px',
                    fontSize: '0.85rem',
                    lineHeight: 1.7,
                  }}
                >
                  {modalData.branchName && (
                    <div>
                      📍 <strong>الفرع المكتشف:</strong> {modalData.branchName}
                    </div>
                  )}
                  {modalData.clientIp && (
                    <div>
                      💻 <strong>عنوان جهازك (IP):</strong> {modalData.clientIp}
                    </div>
                  )}
                  {modalData.busyIp && (
                    <div style={{ color: 'var(--apple-orange, #ff9500)', fontWeight: 700 }}>
                      ⏳ <strong>الجهاز الذي يقوم بالتحميل حالياً:</strong> {modalData.busyIp}
                    </div>
                  )}
                </div>
              )}

              {/* Actions */}
              <div style={{ display: 'flex', gap: '10px' }}>
                {modalData.isError ? (
                  /* Single OK button for Maintenance / Disabled state - no confusing retry loops */
                  <button
                    type="button"
                    onClick={() => setModalOpen(false)}
                    className="btn-apple-download"
                    style={{
                      width: '100%',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      borderRadius: '14px',
                      padding: '12px',
                      fontWeight: 700,
                      fontSize: '0.92rem',
                    }}
                  >
                    <span>حسناً، فهمت</span>
                  </button>
                ) : (
                  /* Retry / Cancel for Branch Congestion */
                  <>
                    <button
                      type="button"
                      onClick={handleRetryInModal}
                      disabled={retrying}
                      className="btn-apple-download"
                      style={{
                        flex: 1,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: '8px',
                        borderRadius: '14px',
                        padding: '12px',
                        fontWeight: 700,
                        fontSize: '0.92rem',
                        cursor: retrying ? 'wait' : 'pointer',
                      }}
                    >
                      {retrying ? (
                        <>
                          <Loader2 size={16} className="animate-spin" />
                          <span>جارِ الفحص...</span>
                        </>
                      ) : (
                        <>
                          <Download size={16} />
                          <span>إعادة المحاولة الآن</span>
                        </>
                      )}
                    </button>

                    <button
                      type="button"
                      onClick={() => setModalOpen(false)}
                      style={{
                        backgroundColor: 'var(--bg-system, #f2f2f7)',
                        color: 'var(--label-primary, #1c1c1e)',
                        border: 'none',
                        borderRadius: '14px',
                        padding: '12px 20px',
                        fontWeight: 700,
                        fontSize: '0.92rem',
                        cursor: 'pointer',
                      }}
                    >
                      إلغاء
                    </button>
                  </>
                )}
              </div>
            </div>
          </div>,
          document.body
        )
      : null;

  return (
    <>
      <a
        href={`/api/portal/download?file=${fileType}`}
        onClick={handleDownloadClick}
        className={className}
        style={{ cursor: loading ? 'wait' : 'pointer', ...style }}
      >
        {loading ? (
          <>
            <Loader2 size={18} className="animate-spin" />
            <span>جارِ التحقق من شبكة الفرع...</span>
          </>
        ) : (
          children || (
            <>
              <Download size={18} />
              <span>
                {fileType === 'windows'
                  ? 'تحميل برنامج الكمبيوتر (EXE)'
                  : 'تحميل تطبيق الموبايل (APK)'}
              </span>
            </>
          )
        )}
      </a>

      {modalPortal}
    </>
  );
}
