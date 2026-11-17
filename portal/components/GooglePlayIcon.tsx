import React from 'react';

export default function GooglePlayIcon({ size = 20, className = '' }: { size?: number; className?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      style={{ flexShrink: 0 }}
    >
      <path
        d="M3.609 1.814A2.08 2.08 0 0 0 3 3.329v17.344c0 .594.234 1.14.61 1.515l9.468-9.469L3.61 1.814Z"
        fill="#00C1FF"
      />
      <path
        d="M16.594 9.203 13.078 12.72l3.516 3.515 4.093-2.328a1.764 1.764 0 0 0 0-3.375l-4.093-2.329Z"
        fill="#FFC400"
      />
      <path
        d="M3.61 22.188c.484.281 1.093.281 1.625-.016l11.359-6.453-3.516-3.516L3.61 22.188Z"
        fill="#00E676"
      />
      <path
        d="m13.078 12.719 3.516-3.516L5.234 2.75A1.758 1.758 0 0 0 3.61 1.813l9.468 10.906Z"
        fill="#FF3D00"
      />
    </svg>
  );
}
