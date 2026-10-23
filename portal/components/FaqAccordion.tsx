'use client';

import React, { useState } from 'react';
import { ChevronDown } from 'lucide-react';

export interface FaqItem {
  question: string;
  answer: React.ReactNode;
}

export default function FaqAccordion({ items }: { items: FaqItem[] }) {
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  const toggle = (idx: number) => {
    setOpenIndex(openIndex === idx ? null : idx);
  };

  return (
    <div className="faq-wrap">
      {items.map((item, idx) => {
        const isOpen = openIndex === idx;
        return (
          <div key={idx} className={`faq-row ${isOpen ? 'active' : ''}`}>
            <div className="faq-q" onClick={() => toggle(idx)} role="button" tabIndex={0}>
              <span>{item.question}</span>
              <ChevronDown
                size={18}
                className={`faq-q-chevron ${isOpen ? 'rotate-180' : ''}`}
                style={{
                  transition: 'transform 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
                  transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
                }}
              />
            </div>
            {isOpen && <div className="faq-a">{item.answer}</div>}
          </div>
        );
      })}
    </div>
  );
}
