#!/usr/bin/env python3
"""Generate cohesive Apple App Store screenshots for 6.9", 6.5", and iPad 13"."""

from __future__ import annotations

import base64
import html
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSETS_ROOT = REPO_ROOT / "app_store_assets"
RAW_CAPTURES = ASSETS_ROOT / "raw_simulator_captures"
ICON_PATH = ASSETS_ROOT / "icons" / "AppIcon-512x512.png"
CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

SPECS = [
    {
        "folder": "iphone_6.9_inch_1320x2868",
        "width": 1320,
        "height": 2868,
        "device": "iphone",
        "capture": RAW_CAPTURES / "iphone_17_pro_max_login.png",
    },
    {
        "folder": "iphone_6.5_inch_1284x2778",
        "width": 1284,
        "height": 2778,
        "device": "iphone",
        "capture": RAW_CAPTURES / "iphone_17_pro_max_login.png",
    },
    {
        "folder": "ipad_13_inch_2064x2752",
        "width": 2064,
        "height": 2752,
        "device": "ipad",
        "capture": RAW_CAPTURES / "ipad_pro_13_login.png",
    },
]


def img_to_data_uri(path: Path) -> str:
    raw = path.read_bytes()
    b64 = base64.b64encode(raw).decode("ascii")
    return f"data:image/png;base64,{b64}"


def build_slide_content(slide_id: str, real_login_uri: str, icon_uri: str) -> dict[str, str]:
    if slide_id == "01_workplace_chat":
        return {
            "theme": "dark",
            "badge": "المراسلة المؤسسية الآمنة",
            "title": "تواصل مؤسسي فوري وآمن",
            "subtitle": "محادثات الأقسام والفروع والمجموعات مع حالة الاتصال لحظة بلحظة",
            "screen_bg": "#F2F2F7",
            "screen_html": f"""
            <div class="app-screen light-ui">
              <div class="ios-statusbar dark-text">
                <span class="sb-time">9:41</span>
                <div class="sb-icons"><span>5G</span><span class="bat">100%</span></div>
              </div>
              <div class="chat-header">
                <div class="chat-title-row">
                  <h1>المحادثات</h1>
                  <div class="header-actions">
                    <span class="pill-btn blue">+ محادثة</span>
                  </div>
                </div>
                <div class="search-bar">🔍 &nbsp;ابحث في الزملاء أو الأقسام...</div>
                <div class="seg-tabs">
                  <span class="seg active">الكل</span>
                  <span class="seg">مباشرة</span>
                  <span class="seg">مجموعات</span>
                  <span class="seg">أقسام</span>
                </div>
              </div>
              <div class="chat-list">
                <div class="chat-row">
                  <div class="avatar blue-av">تق<span class="online-dot"></span></div>
                  <div class="chat-meta">
                    <div class="row-top"><strong>فريق تقنية المعلومات</strong><span class="time">09:40</span></div>
                    <div class="row-bot"><span>تم اعتماد ملف الجرد الشهري بنجاح 📄</span><span class="badge blue">3</span></div>
                  </div>
                </div>
                <div class="chat-row">
                  <div class="avatar green-av">أح<span class="online-dot"></span></div>
                  <div class="chat-meta">
                    <div class="row-top"><strong>أحمد محمود</strong><span class="time">09:34</span></div>
                    <div class="row-bot"><span>🎤 رسالة صوتية (0:24)</span><span class="badge green">1</span></div>
                  </div>
                </div>
                <div class="chat-row">
                  <div class="avatar indigo-av">إد</div>
                  <div class="chat-meta">
                    <div class="row-top"><strong>إدارة الفروع والمشتريات</strong><span class="time">09:12</span></div>
                    <div class="row-bot"><span>سارة: مرفق فواتير التوريد المعتمدة PDF</span><span class="badge gray">5</span></div>
                  </div>
                </div>
                <div class="chat-row">
                  <div class="avatar teal-av">م<span class="online-dot"></span></div>
                  <div class="chat-meta">
                    <div class="row-top"><strong>مريم خالد - الموارد البشرية</strong><span class="time">أمس</span></div>
                    <div class="row-bot"><span>✓✓ تم مراجعة التقرير وإرساله للأرشيف</span></div>
                  </div>
                </div>
                <div class="chat-row">
                  <div class="avatar orange-av">ف</div>
                  <div class="chat-meta">
                    <div class="row-top"><strong>الفرع الرئيسي • العمليات</strong><span class="time">أمس</span></div>
                    <div class="row-bot"><span>تذكير: اجتماع المراجعة الساعة 11:00</span></div>
                  </div>
                </div>
                <div class="chat-row">
                  <div class="avatar purple-av">ع<span class="online-dot"></span></div>
                  <div class="chat-meta">
                    <div class="row-top"><strong>عمر طارق - الدعم الفني</strong><span class="time">الإثنين</span></div>
                    <div class="row-bot"><span>✓✓ جاهز للطباعة على طابعة الدور الثاني</span></div>
                  </div>
                </div>
              </div>
              <div class="bottom-nav">
                <div class="nav-item active"><span class="ni">💬</span><span>المحادثات</span></div>
                <div class="nav-item"><span class="ni">📷</span><span>الماسح</span></div>
                <div class="nav-item"><span class="ni">📁</span><span>الملفات</span></div>
                <div class="nav-item"><span class="ni">⚙️</span><span>الإعدادات</span></div>
              </div>
            </div>
            """,
        }

    if slide_id == "02_conversation_voice":
        return {
            "theme": "light",
            "badge": "مراسلات غنية ورسائل صوتية",
            "title": "رسائل صوتية ومرفقات وتفاعلات ذكية",
            "subtitle": "تشغيل صوتي فوري، مشاركة مستندات PDF، وتفاعلات لحظية بدون انقطاع",
            "screen_bg": "#EEF2F7",
            "screen_html": """
            <div class="app-screen chat-conv-ui">
              <div class="ios-statusbar dark-text">
                <span class="sb-time">9:41</span>
                <div class="sb-icons"><span>5G</span><span class="bat">100%</span></div>
              </div>
              <div class="conv-navbar">
                <span class="back-chev">‹</span>
                <div class="avatar green-av sm">أح<span class="online-dot"></span></div>
                <div class="conv-peer">
                  <strong>أحمد محمود</strong>
                  <span>متصل الآن • قسم العمليات</span>
                </div>
                <span class="nav-icon">🔍</span>
              </div>
              <div class="conv-body">
                <div class="date-chip">اليوم</div>
                <div class="bubble in">
                  <div class="b-text">صباح الخير، هل انتهيت من مسح عقود التوريد للربع الحالي؟</div>
                  <div class="b-time">09:28</div>
                </div>
                <div class="bubble out">
                  <div class="pdf-card">
                    <div class="pdf-badge">PDF</div>
                    <div class="pdf-info">
                      <strong>عقود_التوريد_الممسوحة.pdf</strong>
                      <span>6 صفحات • 2.4 MB</span>
                    </div>
                  </div>
                  <div class="b-text">نعم، تم مسح جميع الصفحات وتحسين الوضوح وإرفاقها هنا.</div>
                  <div class="b-time">09:31 ✓✓</div>
                </div>
                <div class="reaction-row out-align"><span class="react-pill">👍 1</span><span class="react-pill">❤️ 2</span></div>
                <div class="bubble in voice-bubble">
                  <div class="voice-row">
                    <div class="play-btn">▶</div>
                    <div class="waveform">
                      <i style="height:35%"></i><i style="height:75%"></i><i style="height:95%"></i>
                      <i style="height:55%"></i><i style="height:85%"></i><i style="height:40%"></i>
                      <i style="height:90%"></i><i style="height:65%"></i><i style="height:50%"></i>
                      <i style="height:80%"></i><i style="height:35%"></i><i style="height:60%"></i>
                      <i style="height:45%"></i><i style="height:70%"></i>
                    </div>
                    <span class="v-dur">0:24</span>
                  </div>
                  <div class="b-text">ممتاز جداً! الجودة واضحة والنسخة وصلت كاملة للفرع.</div>
                  <div class="b-time">09:34</div>
                </div>
                <div class="bubble out">
                  <div class="b-text">تم أيضاً إرسال نسخة تلقائياً لمركز المستندات ✅</div>
                  <div class="b-time">09:35 ✓✓</div>
                </div>
              </div>
              <div class="composer-bar">
                <span class="comp-ic">📎</span>
                <span class="comp-ic">📷</span>
                <div class="comp-input">اكتب رسالة...</div>
                <span class="comp-mic">🎤</span>
              </div>
            </div>
            """,
        }

    if slide_id == "03_document_scanner":
        return {
            "theme": "dark_emerald",
            "badge": "محرك iOS أصلي • Vision & CoreImage",
            "title": "ماسح مستندات ذكي بدقة احترافية",
            "subtitle": "كشف تلقائي ذكي لأطراف الورقة، فلاتر وضوح متقدمة، وتوقيع إلكتروني فوري",
            "screen_bg": "#06080F",
            "screen_html": """
            <div class="app-screen scanner-ui">
              <div class="ios-statusbar light-text">
                <span class="sb-time">9:41</span>
                <div class="sb-icons"><span>5G</span><span class="bat">100%</span></div>
              </div>
              <div class="scanner-topbar">
                <span class="sc-btn">✕</span>
                <span class="sc-mode-pill">وضع الدفعة • متعدد الصفحات</span>
                <span class="sc-btn">⚡</span>
              </div>
              <div class="scanner-viewport">
                <div class="desk-surface">
                  <div class="paper-doc">
                    <div class="paper-hdr">
                      <div class="p-logo"></div>
                      <div><strong>محضر استلام وأرشفة</strong><span>نموذج رقم INV-2026-884</span></div>
                    </div>
                    <div class="p-line w90"></div>
                    <div class="p-line w75"></div>
                    <div class="p-line w85"></div>
                    <div class="p-box">
                      <div><span>البند: أجهزة مسح وشبكات</span><span>الكمية: 12</span></div>
                      <div><span>القسم: تقنية المعلومات</span><span>الحالة: معتمد ✓</span></div>
                    </div>
                    <div class="p-line w80"></div>
                    <div class="p-line w60"></div>
                    <div class="p-sig">توقيع المستلم: ✍️ معتمد</div>
                  </div>
                  <div class="quad-overlay">
                    <span class="corner tl"></span>
                    <span class="corner tr"></span>
                    <span class="corner bl"></span>
                    <span class="corner br"></span>
                  </div>
                  <div class="detect-chip">✓ تم تحديد أطراف المستند تلقائياً</div>
                </div>
              </div>
              <div class="filter-strip">
                <span class="flt">أصلي</span>
                <span class="flt active">تحسين ذكي</span>
                <span class="flt">رمادي</span>
                <span class="flt">إزالة خط اليد</span>
              </div>
              <div class="scanner-bottom">
                <span class="gal-btn">🖼️</span>
                <div class="shutter-ring"><div class="shutter-core"></div></div>
                <span class="done-pill">تم (3)</span>
              </div>
            </div>
            """,
        }

    if slide_id == "04_operations_center":
        return {
            "theme": "light_teal",
            "badge": "مركز المستندات والأصول والطباعة",
            "title": "مركز المستندات وإدارة العمليات",
            "subtitle": "تصفح الملفات السحابية، جرد الأصول بمسح QR، ومراقبة الطابعات والتذاكر",
            "screen_bg": "#F2F2F7",
            "screen_html": """
            <div class="app-screen ops-ui">
              <div class="ios-statusbar dark-text">
                <span class="sb-time">9:41</span>
                <div class="sb-icons"><span>5G</span><span class="bat">100%</span></div>
              </div>
              <div class="ops-header">
                <h1>مركز المستندات والعمليات</h1>
              </div>
              <div class="bento-hero">
                <div class="hero-top">
                  <div class="avatar blue-av lg">يم</div>
                  <div>
                    <strong>يوسف محمد</strong>
                    <span>مدير الأنظمة • المقر الرئيسي</span>
                  </div>
                </div>
                <div class="hero-stats">
                  <div class="stat-pill"><strong>24</strong><span>ملفات سحابية</span></div>
                  <div class="stat-pill"><strong>6</strong><span>مسح محلي</span></div>
                  <div class="stat-pill"><strong>18</strong><span>أصول مُجرَدة</span></div>
                </div>
              </div>
              <div class="bento-grid">
                <div class="bento-card">
                  <div class="bc-icon green-bg">📄</div>
                  <strong>الماسح الضوئي</strong>
                  <span>مسح ذكي وتصدير PDF</span>
                </div>
                <div class="bento-card">
                  <div class="bc-icon blue-bg">☁️</div>
                  <strong>ملفاتي السحابية</strong>
                  <span>مزامنة فورية ومجلدات</span>
                </div>
                <div class="bento-card">
                  <div class="bc-icon teal-bg">🔲</div>
                  <strong>جرد أصول IT</strong>
                  <span>مسح QR والباركود</span>
                </div>
                <div class="bento-card">
                  <div class="bc-icon indigo-bg">🖨️</div>
                  <strong>الطابعات والتذاكر</strong>
                  <span>متابعة الاستهلاك والبلاغات</span>
                </div>
              </div>
              <div class="recent-card">
                <div class="rc-title">آخر المستندات الممسوحة</div>
                <div class="rc-item"><span>📑 محضر_التوريد_04.pdf</span><span class="rc-tag">تم الرفع</span></div>
                <div class="rc-item"><span>📑 فاتورة_الصيانة_2026.pdf</span><span class="rc-tag">محفوظ</span></div>
              </div>
              <div class="bottom-nav">
                <div class="nav-item"><span class="ni">💬</span><span>المحادثات</span></div>
                <div class="nav-item active"><span class="ni">🏠</span><span>العمليات</span></div>
                <div class="nav-item"><span class="ni">📁</span><span>الملفات</span></div>
                <div class="nav-item"><span class="ni">⚙️</span><span>الإعدادات</span></div>
              </div>
            </div>
            """,
        }

    if slide_id == "05_notifications_privacy":
        return {
            "theme": "dark_indigo",
            "badge": "توافق كامل مع معايير Apple للخصوصية",
            "title": "إشعارات ذكية وتحكم كامل بالخصوصية",
            "subtitle": "نغمات مخصصة، تجميع المحادثات، إدارة الأجهزة المتصلة، وحذف الحساب ذاتياً",
            "screen_bg": "#F2F2F7",
            "screen_html": """
            <div class="app-screen settings-ui">
              <div class="ios-statusbar dark-text">
                <span class="sb-time">9:41</span>
                <div class="sb-icons"><span>5G</span><span class="bat">100%</span></div>
              </div>
              <div class="ops-header">
                <h1>الإعدادات والخصوصية</h1>
              </div>
              <div class="notif-banner">
                <div class="nb-ic">🔔</div>
                <div class="nb-txt">
                  <strong>الإشعارات الفورية مفعلة (APNs)</strong>
                  <span>تجميع ذكي للمحادثات مع دعم الرد السريع</span>
                </div>
                <div class="ios-toggle on"></div>
              </div>
              <div class="grp-label">التنبيهات والنغمات</div>
              <div class="ios-group">
                <div class="ios-row"><span class="ri blue">🗂️</span><span>تجميع إشعارات المحادثات</span><div class="ios-toggle on"></div></div>
                <div class="ios-row"><span class="ri orange">🎵</span><span>نغمة الرسائل</span><span class="val">نغمة رنين ›</span></div>
                <div class="ios-row"><span class="ri green">👁️</span><span>معاينة تفاصيل الرسالة</span><div class="ios-toggle on"></div></div>
              </div>
              <div class="grp-label">الأمان وإدارة الحساب</div>
              <div class="ios-group">
                <div class="ios-row"><span class="ri teal">📱</span><span>الأجهزة المتصلة والجلسات</span><span class="val">iPhone 12 ›</span></div>
                <div class="ios-row"><span class="ri indigo">🛡️</span><span>سياسة الخصوصية وأمان البيانات</span><span class="val">›</span></div>
                <div class="ios-row"><span class="ri red-bg">🚪</span><span class="red-txt">تسجيل الخروج</span><span class="val">›</span></div>
                <div class="ios-row"><span class="ri red-bg">🗑️</span><span class="red-txt bold">حذف الحساب نهائيًا</span><span class="val">›</span></div>
              </div>
            </div>
            """,
        }

    # 06_flexible_login: Embed the REAL live simulator capture cleanly!
    return {
        "theme": "silver",
        "badge": "نسخة حقيقية من التطبيق على iOS",
        "title": "اتصال مرن وآمن بخادم شركتك",
        "subtitle": "اربط تطبيقك بالخادم الداخلي أو السحابي المشفر بمرونة كاملة وبدون تعقيد",
        "screen_bg": "#F2F2F7",
        "screen_html": f'<img class="real-capture" src="{real_login_uri}" alt="Login screen capture" />',
    }


def render_html(spec: dict, slide_id: str, real_login_uri: str, icon_uri: str) -> str:
    w = spec["width"]
    h = spec["height"]
    is_ipad = spec["device"] == "ipad"
    cfg = build_slide_content(slide_id, real_login_uri, icon_uri)
    theme = cfg["theme"]

    bg_css = {
        "dark": "linear-gradient(155deg, #071224 0%, #0D2242 52%, #09172E 100%)",
        "light": "linear-gradient(155deg, #EEF4FC 0%, #FFFFFF 55%, #E3EEF9 100%)",
        "dark_emerald": "linear-gradient(155deg, #061318 0%, #0B262B 55%, #071522 100%)",
        "light_teal": "linear-gradient(155deg, #EFF7F6 0%, #FFFFFF 55%, #E7F0FA 100%)",
        "dark_indigo": "linear-gradient(155deg, #0B1226 0%, #172347 55%, #0B152A 100%)",
        "silver": "linear-gradient(155deg, #EBF0F7 0%, #FFFFFF 60%, #E2EAF4 100%)",
    }[theme]

    is_dark_canvas = theme in ("dark", "dark_emerald", "dark_indigo")
    title_color = "#FFFFFF" if is_dark_canvas else "#0F172A"
    sub_color = "rgba(226, 232, 240, 0.85)" if is_dark_canvas else "#475569"
    badge_bg = "rgba(0, 122, 255, 0.22)" if is_dark_canvas else "rgba(0, 122, 255, 0.11)"
    badge_border = "rgba(96, 165, 250, 0.45)" if is_dark_canvas else "rgba(0, 122, 255, 0.28)"
    badge_color = "#60A5FA" if is_dark_canvas else "#0066CC"
    if theme == "dark_emerald":
        badge_bg = "rgba(16, 185, 129, 0.18)"
        badge_border = "rgba(52, 211, 153, 0.45)"
        badge_color = "#34D399"

    # Layout proportions tailored cleanly for iPhone (tall) vs iPad (4:3)
    if is_ipad:
        pad_top = 86
        title_fs = 74
        sub_fs = 36
        badge_fs = 28
        frame_w = 1480
        frame_h = 1974
        frame_radius = 74
        bezel = 26
        scale_factor = 1.32
    else:
        pad_top = 112 if w >= 1300 else 108
        title_fs = 74 if w >= 1300 else 72
        sub_fs = 34 if w >= 1300 else 33
        badge_fs = 26
        frame_w = int(w * 0.775)
        frame_h = int(frame_w * 2.155)
        frame_radius = 116
        bezel = 24
        scale_factor = 1.0

    # Inner screen logical sizing with crisp proportional transform scaling
    inner_w = frame_w - (bezel * 2)
    inner_h = frame_h - (bezel * 2)
    ui_scale = 1.24 if is_ipad else (inner_w / 975.0)
    logical_w = inner_w / ui_scale
    logical_h = inner_h / ui_scale

    return f"""<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8" />
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  html, body {{
    width: {w}px;
    height: {h}px;
    overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, "SF Arabic", "Geeza Pro", "Helvetica Neue", Arial, sans-serif;
    background: {bg_css};
    -webkit-font-smoothing: antialiased;
  }}
  .canvas {{
    position: relative;
    width: {w}px;
    height: {h}px;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-top: {pad_top}px;
  }}
  .glow-top {{
    position: absolute;
    top: -260px;
    width: 1100px;
    height: 700px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(0,122,255,0.22) 0%, rgba(16,185,129,0.08) 45%, transparent 72%);
    pointer-events: none;
  }}
  .header-block {{
    position: relative;
    z-index: 2;
    width: {int(w * 0.88)}px;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: 22px;
    margin-bottom: {52 if not is_ipad else 44}px;
  }}
  .brand-pill {{
    display: inline-flex;
    align-items: center;
    gap: 14px;
    padding: 12px 28px;
    border-radius: 999px;
    background: {badge_bg};
    border: 2px solid {badge_border};
    color: {badge_color};
    font-size: {badge_fs}px;
    font-weight: 700;
  }}
  .brand-pill img {{
    width: {badge_fs + 14}px;
    height: {badge_fs + 14}px;
    border-radius: 10px;
  }}
  .headline {{
    color: {title_color};
    font-size: {title_fs}px;
    font-weight: 800;
    line-height: 1.24;
    letter-spacing: -0.5px;
  }}
  .subhead {{
    color: {sub_color};
    font-size: {sub_fs}px;
    font-weight: 500;
    line-height: 1.45;
    max-width: {int(w * 0.80)}px;
  }}
  .device-wrap {{
    position: relative;
    z-index: 2;
    margin-top: auto;
    transform: translateY({44 if not is_ipad else 38}px);
    width: {frame_w}px;
    height: {frame_h}px;
    border-radius: {frame_radius}px;
    padding: {bezel}px;
    background: linear-gradient(145deg, #4B5563 0%, #1F2937 45%, #374151 100%);
    box-shadow: 0 42px 120px rgba(0, 0, 0, 0.42), 0 0 0 2px rgba(255,255,255,0.18) inset;
  }}
  .device-screen {{
    position: relative;
    width: 100%;
    height: 100%;
    border-radius: {frame_radius - bezel + 4}px;
    overflow: hidden;
    background: {cfg["screen_bg"]};
  }}
  .dynamic-island {{
    position: absolute;
    top: 24px;
    left: 50%;
    transform: translateX(-50%);
    width: 245px;
    height: 68px;
    background: #000000;
    border-radius: 40px;
    z-index: 50;
    display: {'none' if is_ipad or slide_id == '06_flexible_login' else 'block'};
  }}
  .real-capture {{
    width: 100%;
    height: 100%;
    object-fit: cover;
    object-position: top center;
    display: block;
  }}

  /* Scaled UI interior */
  .app-screen {{
    width: {logical_w:.2f}px;
    height: {logical_h:.2f}px;
    transform: scale({ui_scale:.4f});
    transform-origin: top right;
    display: flex;
    flex-direction: column;
    color: #0F172A;
    background: #F2F2F7;
  }}
  .scanner-ui {{ background: #070A10; color: #FFFFFF; }}
  .ios-statusbar {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: {40 if not is_ipad else 28}px 56px 18px;
    font-size: {30 if not is_ipad else 34}px;
    font-weight: 700;
    direction: ltr;
  }}
  .ios-statusbar.light-text {{ color: #FFFFFF; }}
  .sb-icons {{ display: flex; gap: 18px; align-items: center; font-size: 24px; }}
  .bat {{ background: rgba(52,199,89,0.2); color: #16A34A; padding: 3px 12px; border-radius: 10px; }}
  .light-text .bat {{ background: rgba(52,199,89,0.28); color: #4ADE80; }}

  /* Slide 1: Chat Home */
  .chat-header {{ background: #FFFFFF; padding: 18px 36px 24px; border-bottom: 1.5px solid #E5E7EB; }}
  .chat-title-row {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }}
  .chat-title-row h1 {{ font-size: 50px; font-weight: 800; }}
  .pill-btn.blue {{ background: #007AFF; color: #FFF; padding: 12px 24px; border-radius: 999px; font-size: 25px; font-weight: 700; }}
  .search-bar {{ background: #F1F5F9; color: #64748B; padding: 18px 26px; border-radius: 20px; font-size: 26px; margin-bottom: 20px; }}
  .seg-tabs {{ display: flex; gap: 14px; }}
  .seg {{ background: #F1F5F9; color: #475569; padding: 12px 24px; border-radius: 999px; font-size: 25px; font-weight: 700; }}
  .seg.active {{ background: #007AFF; color: #FFF; }}
  .chat-list {{ flex: 1; background: #FFFFFF; padding: 8px 28px; display: flex; flex-direction: column; gap: 4px; }}
  .chat-row {{ display: flex; align-items: center; gap: 22px; padding: 22px 10px; border-bottom: 1.5px solid #F1F5F9; }}
  .avatar {{
    position: relative; width: 100px; height: 100px; border-radius: 30px;
    display: flex; align-items: center; justify-content: center;
    color: #FFF; font-size: 36px; font-weight: 800; flex-shrink: 0;
  }}
  .avatar.sm {{ width: 76px; height: 76px; border-radius: 22px; font-size: 28px; }}
  .avatar.lg {{ width: 108px; height: 108px; border-radius: 32px; font-size: 38px; }}
  .blue-av {{ background: linear-gradient(135deg,#007AFF,#2563EB); }}
  .green-av {{ background: linear-gradient(135deg,#10B981,#059669); }}
  .indigo-av {{ background: linear-gradient(135deg,#6366F1,#4338CA); }}
  .teal-av {{ background: linear-gradient(135deg,#14B8A6,#0F766E); }}
  .orange-av {{ background: linear-gradient(135deg,#F59E0B,#D97706); }}
  .purple-av {{ background: linear-gradient(135deg,#8B5CF6,#6D28D9); }}
  .online-dot {{
    position: absolute; bottom: -2px; left: -2px; width: 24px; height: 24px;
    border-radius: 50%; background: #22C55E; border: 4px solid #FFF;
  }}
  .chat-meta {{ flex: 1; display: flex; flex-direction: column; gap: 10px; min-width: 0; }}
  .row-top {{ display: flex; justify-content: space-between; align-items: center; font-size: 31px; }}
  .row-top .time {{ color: #64748B; font-size: 23px; font-weight: 600; }}
  .row-bot {{ display: flex; justify-content: space-between; align-items: center; color: #64748B; font-size: 26px; }}
  .badge {{ min-width: 44px; height: 44px; padding: 0 12px; border-radius: 22px; color: #FFF; font-size: 23px; font-weight: 800; display: inline-flex; align-items: center; justify-content: center; }}
  .badge.blue {{ background: #007AFF; }}
  .badge.green {{ background: #10B981; }}
  .badge.gray {{ background: #64748B; }}
  .bottom-nav {{
    background: rgba(255,255,255,0.96); border-top: 1.5px solid #E5E7EB;
    display: flex; justify-content: space-around; padding: 18px 16px 34px;
  }}
  .nav-item {{ display: flex; flex-direction: column; align-items: center; gap: 6px; color: #64748B; font-size: 22px; font-weight: 600; }}
  .nav-item.active {{ color: #007AFF; }}
  .nav-item .ni {{ font-size: 36px; }}

  /* Slide 2: Conversation */
  .conv-navbar {{
    display: flex; align-items: center; gap: 20px; padding: 18px 32px;
    background: #FFFFFF; border-bottom: 1.5px solid #E5E7EB;
  }}
  .back-chev {{ font-size: 56px; color: #007AFF; line-height: 1; }}
  .conv-peer {{ flex: 1; display: flex; flex-direction: column; gap: 4px; }}
  .conv-peer strong {{ font-size: 32px; }}
  .conv-peer span {{ font-size: 22px; color: #16A34A; font-weight: 600; }}
  .nav-icon {{ font-size: 34px; }}
  .conv-body {{ flex: 1; padding: 28px 30px; display: flex; flex-direction: column; gap: 22px; background: #EAEFF6; }}
  .date-chip {{ align-self: center; background: rgba(15,23,42,0.08); color: #475569; padding: 8px 24px; border-radius: 999px; font-size: 22px; font-weight: 700; }}
  .bubble {{ max-width: 82%; padding: 22px 26px; border-radius: 28px; display: flex; flex-direction: column; gap: 10px; box-shadow: 0 4px 16px rgba(15,23,42,0.06); }}
  .bubble.in {{ align-self: flex-start; background: #FFFFFF; color: #0F172A; border-bottom-right-radius: 8px; }}
  .bubble.out {{ align-self: flex-end; background: linear-gradient(135deg,#007AFF,#0062CC); color: #FFFFFF; border-bottom-left-radius: 8px; }}
  .b-text {{ font-size: 29px; line-height: 1.45; }}
  .b-time {{ font-size: 21px; opacity: 0.72; align-self: flex-end; }}
  .pdf-card {{
    display: flex; align-items: center; gap: 18px; padding: 16px 20px; border-radius: 20px;
    background: rgba(255,255,255,0.18); border: 1.5px solid rgba(255,255,255,0.28);
  }}
  .pdf-badge {{ background: #EF4444; color: #FFF; font-weight: 800; padding: 14px 18px; border-radius: 14px; font-size: 24px; }}
  .pdf-info {{ display: flex; flex-direction: column; gap: 4px; }}
  .pdf-info strong {{ font-size: 25px; }}
  .pdf-info span {{ font-size: 21px; opacity: 0.88; }}
  .reaction-row {{ display: flex; gap: 10px; margin-top: -12px; }}
  .out-align {{ align-self: flex-end; }}
  .react-pill {{ background: #FFFFFF; padding: 6px 16px; border-radius: 999px; font-size: 23px; font-weight: 700; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }}
  .voice-row {{ display: flex; align-items: center; gap: 18px; padding: 8px 4px; }}
  .play-btn {{ width: 62px; height: 62px; border-radius: 50%; background: #007AFF; color: #FFF; display: flex; align-items: center; justify-content: center; font-size: 26px; flex-shrink: 0; }}
  .waveform {{ display: flex; align-items: center; gap: 7px; height: 54px; flex: 1; }}
  .waveform i {{ display: block; width: 8px; background: #007AFF; border-radius: 4px; }}
  .v-dur {{ font-size: 23px; font-weight: 700; color: #007AFF; }}
  .composer-bar {{
    background: #FFFFFF; border-top: 1.5px solid #E5E7EB;
    padding: 18px 26px 34px; display: flex; align-items: center; gap: 18px;
  }}
  .comp-ic {{ font-size: 36px; }}
  .comp-input {{ flex: 1; background: #F1F5F9; color: #64748B; padding: 18px 24px; border-radius: 999px; font-size: 27px; }}
  .comp-mic {{ width: 68px; height: 68px; border-radius: 50%; background: #007AFF; color: #FFF; display: flex; align-items: center; justify-content: center; font-size: 32px; }}

  /* Slide 3: Document Scanner */
  .scanner-topbar {{ display: flex; justify-content: space-between; align-items: center; padding: 14px 36px 22px; }}
  .sc-btn {{ width: 64px; height: 64px; border-radius: 50%; background: rgba(255,255,255,0.14); display: flex; align-items: center; justify-content: center; font-size: 30px; }}
  .sc-mode-pill {{ background: rgba(0,230,118,0.18); border: 2px solid #00E676; color: #00E676; padding: 12px 28px; border-radius: 999px; font-size: 24px; font-weight: 700; }}
  .scanner-viewport {{ flex: 1; padding: 20px 36px; display: flex; align-items: center; justify-content: center; }}
  .desk-surface {{
    position: relative; width: 100%; height: 100%; border-radius: 34px;
    background: radial-gradient(circle at center, #1E293B 0%, #0F172A 100%);
    display: flex; align-items: center; justify-content: center; overflow: hidden;
  }}
  .paper-doc {{
    width: 78%; height: 78%; background: #FFFFFF; color: #0F172A; border-radius: 16px;
    padding: 42px; display: flex; flex-direction: column; gap: 22px;
    box-shadow: 0 24px 60px rgba(0,0,0,0.55);
  }}
  .paper-hdr {{ display: flex; align-items: center; gap: 18px; border-bottom: 2px solid #E2E8F0; padding-bottom: 18px; }}
  .p-logo {{ width: 58px; height: 58px; border-radius: 14px; background: linear-gradient(135deg,#0F172A,#007AFF); }}
  .paper-hdr strong {{ display: block; font-size: 28px; }}
  .paper-hdr span {{ font-size: 20px; color: #64748B; }}
  .p-line {{ height: 18px; border-radius: 9px; background: #E2E8F0; }}
  .w90 {{ width: 92%; }} .w85 {{ width: 85%; }} .w80 {{ width: 80%; }} .w75 {{ width: 75%; }} .w60 {{ width: 60%; }}
  .p-box {{
    background: #F8FAFC; border: 2px solid #CBD5E1; border-radius: 16px; padding: 20px;
    display: flex; flex-direction: column; gap: 12px; font-size: 22px; font-weight: 600;
  }}
  .p-box div {{ display: flex; justify-content: space-between; }}
  .p-sig {{ margin-top: auto; color: #059669; font-size: 26px; font-weight: 800; align-self: flex-end; }}
  .quad-overlay {{
    position: absolute; width: 82%; height: 81%;
    border: 5px solid #00E676; border-radius: 18px;
    background: rgba(0,230,118,0.12);
    box-shadow: 0 0 30px rgba(0,230,118,0.35);
  }}
  .corner {{ position: absolute; width: 26px; height: 26px; border-radius: 50%; background: #00E676; border: 4px solid #FFF; }}
  .tl {{ top: -13px; left: -13px; }} .tr {{ top: -13px; right: -13px; }}
  .bl {{ bottom: -13px; left: -13px; }} .br {{ bottom: -13px; right: -13px; }}
  .detect-chip {{
    position: absolute; bottom: 26px; background: rgba(0,0,0,0.75); border: 1.5px solid #00E676;
    color: #00E676; padding: 10px 24px; border-radius: 999px; font-size: 23px; font-weight: 700;
  }}
  .filter-strip {{ display: flex; justify-content: center; gap: 16px; padding: 18px 24px; }}
  .flt {{ background: rgba(255,255,255,0.12); color: #CBD5E1; padding: 12px 24px; border-radius: 999px; font-size: 23px; font-weight: 600; }}
  .flt.active {{ background: #00E676; color: #052E16; font-weight: 800; }}
  .scanner-bottom {{ display: flex; justify-content: space-between; align-items: center; padding: 18px 46px 42px; }}
  .gal-btn {{ width: 86px; height: 86px; border-radius: 26px; background: rgba(255,255,255,0.16); display: flex; align-items: center; justify-content: center; font-size: 38px; }}
  .shutter-ring {{ width: 128px; height: 128px; border-radius: 50%; border: 6px solid #00E676; padding: 8px; display: flex; align-items: center; justify-content: center; }}
  .shutter-core {{ width: 100%; height: 100%; border-radius: 50%; background: #FFFFFF; }}
  .done-pill {{ background: #00E676; color: #052E16; padding: 20px 34px; border-radius: 999px; font-size: 28px; font-weight: 800; }}

  /* Slide 4: Operations Center */
  .ops-header {{ padding: 18px 36px; }}
  .ops-header h1 {{ font-size: 42px; font-weight: 800; }}
  .bento-hero {{ margin: 8px 30px 22px; background: #FFFFFF; border-radius: 34px; padding: 28px; border: 1.5px solid #E5E7EB; display: flex; flex-direction: column; gap: 24px; }}
  .hero-top {{ display: flex; align-items: center; gap: 22px; }}
  .hero-top strong {{ display: block; font-size: 34px; }}
  .hero-top span {{ font-size: 24px; color: #64748B; }}
  .hero-stats {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }}
  .stat-pill {{ background: #F8FAFC; border: 1.5px solid #E2E8F0; border-radius: 22px; padding: 18px 12px; text-align: center; display: flex; flex-direction: column; gap: 4px; }}
  .stat-pill strong {{ font-size: 36px; color: #007AFF; }}
  .stat-pill span {{ font-size: 21px; color: #64748B; font-weight: 600; }}
  .bento-grid {{ margin: 0 30px 22px; display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }}
  .bento-card {{ background: #FFFFFF; border: 1.5px solid #E5E7EB; border-radius: 32px; padding: 28px; display: flex; flex-direction: column; gap: 12px; }}
  .bc-icon {{ width: 78px; height: 78px; border-radius: 22px; display: flex; align-items: center; justify-content: center; font-size: 38px; }}
  .green-bg {{ background: rgba(16,185,129,0.14); }}
  .blue-bg {{ background: rgba(0,122,255,0.14); }}
  .teal-bg {{ background: rgba(20,184,166,0.14); }}
  .indigo-bg {{ background: rgba(99,102,241,0.14); }}
  .bento-card strong {{ font-size: 30px; }}
  .bento-card span {{ font-size: 23px; color: #64748B; }}
  .recent-card {{ margin: 0 30px auto; background: #FFFFFF; border: 1.5px solid #E5E7EB; border-radius: 32px; padding: 26px 28px; display: flex; flex-direction: column; gap: 16px; }}
  .rc-title {{ font-size: 26px; font-weight: 800; color: #334155; }}
  .rc-item {{ display: flex; justify-content: space-between; align-items: center; font-size: 25px; padding: 14px 0; border-top: 1.5px solid #F1F5F9; }}
  .rc-tag {{ background: rgba(16,185,129,0.14); color: #059669; padding: 6px 16px; border-radius: 999px; font-size: 21px; font-weight: 700; }}

  /* Slide 5: Notifications & Privacy */
  .notif-banner {{
    margin: 8px 30px 26px; background: linear-gradient(135deg,#EFF6FF,#ECFDF5);
    border: 2px solid rgba(0,122,255,0.22); border-radius: 30px; padding: 26px;
    display: flex; align-items: center; gap: 20px;
  }}
  .nb-ic {{ width: 74px; height: 74px; border-radius: 20px; background: rgba(0,122,255,0.15); display: flex; align-items: center; justify-content: center; font-size: 36px; }}
  .nb-txt {{ flex: 1; display: flex; flex-direction: column; gap: 6px; }}
  .nb-txt strong {{ font-size: 29px; }}
  .nb-txt span {{ font-size: 23px; color: #475569; }}
  .ios-toggle {{ width: 92px; height: 54px; border-radius: 30px; background: #34C759; position: relative; flex-shrink: 0; }}
  .ios-toggle::after {{ content: ""; position: absolute; top: 5px; left: 5px; width: 44px; height: 44px; border-radius: 50%; background: #FFF; box-shadow: 0 2px 6px rgba(0,0,0,0.2); }}
  .grp-label {{ margin: 8px 42px 12px; font-size: 24px; font-weight: 700; color: #64748B; }}
  .ios-group {{ margin: 0 30px 26px; background: #FFFFFF; border-radius: 28px; border: 1.5px solid #E5E7EB; overflow: hidden; }}
  .ios-row {{ display: flex; align-items: center; gap: 20px; padding: 24px 26px; border-bottom: 1.5px solid #F1F5F9; font-size: 28px; font-weight: 600; }}
  .ios-row:last-child {{ border-bottom: none; }}
  .ios-row span:nth-child(2) {{ flex: 1; }}
  .ri {{ width: 56px; height: 56px; border-radius: 14px; display: flex; align-items: center; justify-content: center; font-size: 28px; }}
  .ri.blue {{ background: rgba(0,122,255,0.14); }}
  .ri.orange {{ background: rgba(255,149,0,0.14); }}
  .ri.green {{ background: rgba(52,199,89,0.14); }}
  .ri.teal {{ background: rgba(20,184,166,0.14); }}
  .ri.indigo {{ background: rgba(88,86,214,0.14); }}
  .ri.red-bg {{ background: rgba(220,38,38,0.12); }}
  .val {{ color: #64748B; font-size: 25px; }}
  .red-txt {{ color: #DC2626; }}
  .bold {{ font-weight: 800; }}
</style>
</head>
<body>
  <div class="canvas">
    <div class="glow-top"></div>
    <div class="header-block">
      <div class="brand-pill">
        <img src="{icon_uri}" alt="iSmart" />
        <span>{html.escape(cfg["badge"])}</span>
      </div>
      <div class="headline">{html.escape(cfg["title"])}</div>
      <div class="subhead">{html.escape(cfg["subtitle"])}</div>
    </div>
    <div class="device-wrap">
      <div class="device-screen">
        <div class="dynamic-island"></div>
        {cfg["screen_html"]}
      </div>
    </div>
  </div>
</body>
</html>"""


def main() -> None:
    if not Path(CHROME_BIN).exists():
        raise FileNotFoundError(f"Chrome not found at {CHROME_BIN}")
    if not ICON_PATH.exists():
        raise FileNotFoundError(f"Marketing icon missing: {ICON_PATH}")

    icon_uri = img_to_data_uri(ICON_PATH)
    slide_ids = [
        "01_workplace_chat",
        "02_conversation_voice",
        "03_document_scanner",
        "04_operations_center",
        "05_notifications_privacy",
        "06_flexible_login",
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        for spec in SPECS:
            out_dir = ASSETS_ROOT / spec["folder"]
            out_dir.mkdir(parents=True, exist_ok=True)
            capture_path: Path = spec["capture"]
            if not capture_path.exists():
                raise FileNotFoundError(f"Missing simulator capture: {capture_path}")
            real_login_uri = img_to_data_uri(capture_path)

            w, h = spec["width"], spec["height"]
            for slide_id in slide_ids:
                html_path = tmp / f"{spec['folder']}_{slide_id}.html"
                raw_shot = tmp / f"{spec['folder']}_{slide_id}_raw.png"
                final_shot = out_dir / f"{slide_id}.png"

                html_path.write_text(
                    render_html(spec, slide_id, real_login_uri, icon_uri),
                    encoding="utf-8",
                )
                cmd = [
                    CHROME_BIN,
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    "--no-sandbox",
                    "--force-device-scale-factor=1",
                    f"--window-size={w},{h}",
                    f"--screenshot={raw_shot}",
                    html_path.as_uri(),
                ]
                subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                # Enforce exact WxH dimensions and 24-bit opaque RGB (hasAlpha: no)
                with Image.open(raw_shot) as im:
                    rgb = im.convert("RGB")
                    if rgb.size != (w, h):
                        rgb = rgb.resize((w, h), Image.Resampling.LANCZOS)
                    rgb.save(final_shot, format="PNG", optimize=True)
                print(f"Created {final_shot.relative_to(REPO_ROOT)} ({w}x{h})")


if __name__ == "__main__":
    main()
