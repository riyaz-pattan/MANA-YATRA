import { useState } from 'react';
import './ForRiders.css';

const biddingSteps = [
  {
    number: 1,
    icon: '📍',
    title: 'Enter your destination',
    desc: 'Open the Gaman app, enter your pickup and drop-off locations. Our smart search auto-completes addresses for you.',
  },
  {
    number: 2,
    icon: '📡',
    title: 'Request goes to nearby drivers',
    desc: 'Your ride request is broadcast to all verified drivers in your area. They can see the trip distance and route.',
  },
  {
    number: 3,
    icon: '💰',
    title: 'Drivers place their bids',
    desc: 'Multiple drivers compete by offering their best price. You see each bid along with the driver\'s rating and ETA.',
  },
  {
    number: 4,
    icon: '✅',
    title: 'Pick the bid you like',
    desc: 'Choose based on price, rating, or arrival time — it\'s entirely your call. No surge pricing, no hidden fees.',
  },
  {
    number: 5,
    icon: '🚗',
    title: 'Track & ride',
    desc: 'Track your driver in real-time as they approach. Share your ride status with emergency contacts for extra safety.',
  },
  {
    number: 6,
    icon: '💵',
    title: 'Pay & rate',
    desc: 'Pay via cash or UPI directly to the driver. Rate your experience to help build a trusted community.',
  },
];

const safetyFeatures = [
  {
    icon: '🔐',
    title: 'OTP Verification',
    desc: 'Every ride starts with a unique OTP that the rider shares with the driver. No one else can start your trip.',
  },
  {
    icon: '📍',
    title: 'Live Tracking',
    desc: 'Track your ride in real-time on the map. Share your live location with friends and family for complete peace of mind.',
  },
  {
    icon: '🚨',
    title: 'Emergency SOS',
    desc: 'One-tap SOS button instantly shares your live location and ride details with your emergency contacts.',
  },
  {
    icon: '✅',
    title: 'Verified Drivers',
    desc: 'All drivers go through rigorous KYC verification — Aadhaar, driving license, and photo verification before they can accept rides.',
  },
];

const riderFaqs = [
  {
    q: 'How is Gaman different from other ride-hailing apps?',
    a: 'Gaman uses a transparent bidding system — drivers compete to offer you the best price. There\'s no surge pricing and no hidden charges. You always see the real price upfront.',
  },
  {
    q: 'How do I know which bid to accept?',
    a: 'Each bid shows the driver\'s offered price, their rating, and estimated time of arrival. You can choose based on whatever matters most to you — lowest price, highest rating, or fastest pickup.',
  },
  {
    q: 'What payment methods can I use?',
    a: 'Currently, Gaman supports cash and UPI payments. You pay the driver directly — no middleman holds your money. We\'re working on adding more payment options soon.',
  },
  {
    q: 'Is it safe to ride with Gaman?',
    a: 'Absolutely. All drivers are KYC-verified (Aadhaar + DL + Photo). Every ride has OTP verification, real-time tracking, and an SOS emergency button that shares your location with your contacts.',
  },
  {
    q: 'What if no driver bids on my ride?',
    a: 'Our system broadcasts your request to all nearby drivers. In most cases, you\'ll receive multiple bids within a minute. If demand is high, try again after a few moments.',
  },
  {
    q: 'Can I cancel a ride after accepting a bid?',
    a: 'Yes, you can cancel a ride before the driver arrives at the pickup location. We encourage responsible cancellations to maintain a healthy platform for everyone.',
  },
  {
    q: 'How do I contact my driver?',
    a: 'Once you accept a bid, you can call or message your driver directly through the app. The driver\'s contact details are visible on the ride screen.',
  },
];

export default function ForRiders() {
  const [openFaq, setOpenFaq] = useState(null);

  return (
    <div className="for-riders-page">
      {/* Hero Section */}
      <section className="section fr-hero">
        <div className="container">
          <span className="badge-purple">🚶 For Riders</span>
          <h1>
            Your ride. Your price.<br />
            <span className="fr-gradient-text">Your choice.</span>
          </h1>
          <p className="fr-hero-sub">
            No surge pricing, no hidden fees. Drivers bid their best price, and you
            pick the one that works for you.
          </p>
          <div className="fr-hero-actions">
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-primary"
            >
              📱 Download Gaman
            </a>
            <a href="#how-bidding-works" className="btn btn-outline">
              See How It Works ↓
            </a>
          </div>
        </div>
      </section>

      {/* How Bidding Works Section */}
      <section className="section fr-bidding" id="how-bidding-works">
        <div className="container">
          <h2 className="fr-section-title">
            How <span className="fr-gradient-text">Bidding</span> Works
          </h2>
          <p className="fr-section-subtitle">
            A simple, transparent process that puts you in control of your ride and your fare.
          </p>
          <div className="fr-bidding-timeline">
            {biddingSteps.map((step) => (
              <div className="fr-timeline-step" key={step.number}>
                <div className="fr-timeline-marker">
                  <div className="fr-timeline-number">{step.number}</div>
                  <div className="fr-timeline-line" />
                </div>
                <div className="fr-timeline-content">
                  <div className="fr-timeline-icon">{step.icon}</div>
                  <h3>{step.title}</h3>
                  <p>{step.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Safety Features Section */}
      <section className="section fr-safety">
        <div className="container">
          <h2 className="fr-section-title fr-title-dark">
            Your Safety, <span className="fr-gradient-text">Our Priority</span>
          </h2>
          <p className="fr-section-subtitle fr-subtitle-dark">
            Every ride on Gaman is backed by multiple layers of safety and verification.
          </p>
          <div className="fr-safety-grid">
            {safetyFeatures.map((feature, i) => (
              <div className="fr-safety-card" key={i}>
                <div className="fr-safety-icon">{feature.icon}</div>
                <h3>{feature.title}</h3>
                <p>{feature.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Payment Methods Section */}
      <section className="section fr-payment">
        <div className="container">
          <h2 className="fr-section-title">
            Pay <span className="fr-gradient-text">Your Way</span>
          </h2>
          <p className="fr-section-subtitle">
            Simple, direct payments with no middleman. Your money goes straight to the driver.
          </p>
          <div className="fr-payment-cards">
            <div className="fr-payment-card">
              <div className="fr-payment-icon">💵</div>
              <h3>Cash</h3>
              <p>
                Pay your driver in cash at the end of the ride. No wallet top-ups,
                no minimum balance required. Simple and straightforward.
              </p>
            </div>
            <div className="fr-payment-card">
              <div className="fr-payment-icon">📱</div>
              <h3>UPI</h3>
              <p>
                Pay instantly via any UPI app — Google Pay, PhonePe, Paytm, or any other.
                Scan the driver's QR or use their UPI ID directly.
              </p>
            </div>
          </div>
          <div className="fr-payment-note">
            <span className="badge-purple">🔒 Direct Payment</span>
            <p>
              Gaman never holds your payment. Every rupee goes directly from you to the driver —
              no deductions, no delays.
            </p>
          </div>
        </div>
      </section>

      {/* Rider FAQ Section */}
      <section className="section fr-faq">
        <div className="container">
          <h2 className="fr-section-title fr-title-white">
            Rider <span className="fr-gradient-text">FAQs</span>
          </h2>
          <p className="fr-section-subtitle fr-subtitle-white">
            Everything you need to know before your first Gaman ride.
          </p>
          <div className="fr-faq-list">
            {riderFaqs.map((faq, i) => (
              <div
                className={`fr-faq-item ${openFaq === i ? 'open' : ''}`}
                key={i}
              >
                <button
                  className="fr-faq-question"
                  onClick={() => setOpenFaq(openFaq === i ? null : i)}
                >
                  <span>{faq.q}</span>
                  <span className="fr-faq-toggle">+</span>
                </button>
                <div className="fr-faq-answer">
                  <p>{faq.a}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Download CTA Section */}
      <section className="section fr-cta">
        <div className="container">
          <h2>Ready for a Fairer Ride?</h2>
          <p>
            Download Gaman and experience transparent, bid-based rides with no surge pricing.
          </p>
          <a
            href="https://play.google.com/store"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-dark"
          >
            📱 Download Gaman
          </a>
        </div>
      </section>
    </div>
  );
}
