import { useState } from 'react';
import PricingCards from '../components/PricingCards';
import './Pricing.css';

const pricingFaqs = [
  {
    q: 'What happens after the free trial?',
    a: 'After your 7-day free trial ends, you can choose any subscription plan — daily, weekly, or monthly — to continue using Gaman. There\'s no automatic charge. You decide when and how to subscribe.',
  },
  {
    q: 'Can I switch plans?',
    a: 'Absolutely! You can switch between daily, weekly, and monthly plans at any time. Your current plan will remain active until it expires, and you can choose a different plan for the next cycle.',
  },
  {
    q: 'Is there a refund policy?',
    a: 'Since our plans are very affordable and short-term, we generally don\'t offer refunds. However, if you face any issues, reach out to our support team and we\'ll do our best to help.',
  },
  {
    q: 'Why subscription instead of commission?',
    a: 'Commission-based platforms take 20-30% of every fare, which adds up to thousands of rupees per month. Our flat subscription means you keep 100% of your earnings. The more rides you do, the more you save compared to commission models.',
  },
  {
    q: 'Are there any hidden fees?',
    a: 'None at all. The subscription price you see is what you pay. No per-ride cuts, no surge fees, no platform charges. What you earn from riders is entirely yours.',
  },
  {
    q: 'What payment methods do you accept for subscriptions?',
    a: 'We accept all UPI apps, debit cards, credit cards, and net banking through our secure Razorpay payment gateway. All transactions are encrypted and secure.',
  },
];

export default function Pricing() {
  const [openFaq, setOpenFaq] = useState(null);

  return (
    <div className="pricing-page">
      {/* Hero Section */}
      <section className="pricing-hero">
        <div className="container">
          <span className="badge-zero">💰 Zero Commission Platform</span>
          <h1>Simple, honest pricing</h1>
          <p className="pricing-hero-subtitle">
            No hidden fees. No per-ride cuts. Ever.
          </p>
        </div>
      </section>

      {/* Pricing Cards Section */}
      <section className="section pricing-cards-section">
        <div className="container">
          <h2 className="pricing-section-title">Choose Your Plan</h2>
          <p className="pricing-section-subtitle">
            Affordable subscriptions designed for drivers who want to keep every rupee they earn.
          </p>
          <PricingCards />
        </div>
      </section>

      {/* Free Trial Details Section */}
      <section className="section pricing-trial-section">
        <div className="container">
          <div className="trial-content">
            <div className="trial-text-block">
              <span className="badge-secondary">🎉 Free for 7 Days</span>
              <h2>Start driving with zero risk</h2>
              <p className="trial-description">
                Every new driver gets a full 7-day free trial. No strings attached — just download the app, sign up, and start earning immediately.
              </p>
            </div>
            <div className="trial-features-grid">
              <div className="trial-feature-card card-light">
                <div className="trial-feature-icon">💳</div>
                <h3>No Payment Needed</h3>
                <p>No credit card, no deposit, no advance payment. Your trial starts the moment you sign up.</p>
              </div>
              <div className="trial-feature-card card-light">
                <div className="trial-feature-icon">🔓</div>
                <h3>Full Access</h3>
                <p>Get complete access to all features — ride requests, bidding, navigation, earnings dashboard, everything.</p>
              </div>
              <div className="trial-feature-card card-light">
                <div className="trial-feature-icon">✋</div>
                <h3>Cancel Anytime</h3>
                <p>Not for you? No worries. There's no obligation to continue after the trial. No questions asked.</p>
              </div>
              <div className="trial-feature-card card-light">
                <div className="trial-feature-icon">💯</div>
                <h3>Keep 100% Earnings</h3>
                <p>During the trial and after — every rupee riders pay goes directly to you. Zero commission, always.</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section className="section pricing-faq-section">
        <div className="container">
          <h2>Pricing <span className="pricing-faq-accent">FAQ</span></h2>
          <p className="pricing-faq-subtitle">
            Common questions about our plans and billing.
          </p>
          <div className="pricing-faq-list">
            {pricingFaqs.map((faq, i) => (
              <div
                className={`pricing-faq-item ${openFaq === i ? 'open' : ''}`}
                key={i}
              >
                <button
                  className="pricing-faq-question"
                  onClick={() => setOpenFaq(openFaq === i ? null : i)}
                >
                  <span>{faq.q}</span>
                  <span className="pricing-faq-toggle">+</span>
                </button>
                <div className="pricing-faq-answer">
                  <p>{faq.a}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="section pricing-cta-section">
        <div className="container">
          <h2>Start your free trial today</h2>
          <p>Download Gaman Driver, sign up, and start earning — all in under 5 minutes.</p>
          <a
            href="https://play.google.com/store"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-dark"
          >
            📱 Download on Google Play
          </a>
        </div>
      </section>
    </div>
  );
}
