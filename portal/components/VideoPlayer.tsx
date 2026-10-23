'use client';

import React, { useRef } from 'react';
import { useToast } from './Toast';
import Link from 'next/link';

export interface Chapter {
  time: number;
  label: string;
}

interface VideoPlayerProps {
  id: string;
  src: string;
  poster?: string;
  tag: string;
  tagType: 'win' | 'mob';
  title: string;
  description: string;
  chapters: Chapter[];
  guideLink: string;
  guideLinkLabel: string;
  downloadLink: string;
  downloadLinkLabel: string;
}

export default function VideoPlayer({
  id,
  src,
  poster = '/assets/images/logo.png',
  tag,
  tagType,
  title,
  description,
  chapters,
  guideLink,
  guideLinkLabel,
  downloadLink,
  downloadLinkLabel,
}: VideoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const { showToast } = useToast();

  const handleSeek = (time: number, label: string) => {
    if (videoRef.current) {
      videoRef.current.currentTime = time;
      videoRef.current.play().catch(() => {});
      videoRef.current.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      showToast(`تم الانتقال إلى الدقيقة: ${label}`);
    }
  };

  return (
    <div className="video-apple-card">
      <div className="video-screen">
        <video
          ref={videoRef}
          id={id}
          controls
          preload="metadata"
          poster={poster}
          playsInline
        >
          <source src={src} type="video/mp4" />
          متصفحك لا يدعم تشغيل مقاطع الفيديو مباشرة.
        </video>
      </div>

      <div className="video-details">
        <span className={`video-tag-pill ${tagType === 'win' ? 'tag-win' : 'tag-mob'}`}>
          {tag}
        </span>
        <h4>{title}</h4>
        <p>{description}</p>

        {/* Chapter Scrubbing Pills */}
        <div className="chapter-box">
          <div className="chapter-title">
            ⏱️ محاور الفيديو (اضغط للقفز للدقيقة):
          </div>
          <div className="chapter-pills">
            {chapters.map((ch, idx) => (
              <button
                key={idx}
                type="button"
                className="chapter-btn"
                onClick={() => handleSeek(ch.time, ch.label)}
              >
                {ch.label}
              </button>
            ))}
          </div>
        </div>

        {/* Bottom Action Links */}
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            borderTop: '1px solid var(--hairline-subtle)',
            paddingTop: '12px',
            marginTop: 'auto',
          }}
        >
          <Link
            href={guideLink}
            style={{
              fontSize: '0.82rem',
              fontWeight: 700,
              color: tagType === 'win' ? 'var(--apple-blue)' : 'var(--apple-green)',
            }}
          >
            {guideLinkLabel} ←
          </Link>
          <a
            href={downloadLink}
            style={{
              fontSize: '0.8rem',
              color: 'var(--label-secondary)',
              textDecoration: 'underline',
            }}
            download
          >
            {downloadLinkLabel}
          </a>
        </div>
      </div>
    </div>
  );
}
