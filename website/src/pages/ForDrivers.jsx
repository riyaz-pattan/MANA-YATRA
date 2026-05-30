import { useState } from 'react';
import PricingCards from '../components/PricingCards';
import EarningsCalculator from '../components/EarningsCalculator';
import './ForDrivers.css';

const kycSteps = [
  {
    number: 1,
    icon: '📲',
    title: 'Download Gaman Driver from Play Store',
    desc: 'Search for "Gaman Driver" on Google Play Store and install the app on your Android device.',
  },
  {
    number: 2,
    icon: '📱',
    title: 'Register with your phone number',
    desc: 'Enter your mobile number and verify it with a one-time OTP sent via SMS.',
  },
  {
    number: 3,
    icon: '🪪',
    title: 'Upload Aadhaar card photo',
    desc: 'Take a clear photo of the front and back of your Aadhaar card for identity verification.',
  },
  {
    number: 4,
    icon: '🪪',
    title: 'Upload Driving License',
    desc: 'Upload a clear photo of your valid driving license. Make sure it matches your vehicle category.',
  },
  {
    number: 5,
    icon: '📸',
    title: 'Upload vehicle photo and profile selfie',
    desc: 'Take a photo of your vehicle and a clear selfie. This helps riders identify you and your car.',
  },
  {
    number: 6,
    icon: '✅',
    title: 'Wait for admin verification',
    desc: 'Our team reviews your documents and approves your profile — usually within 24 hours.',
  },
];

const driverFaqs = [
  {
    q: 'How much does it cost to join Gaman?',
    a: 'Nothing upfront! New drivers get a 7-day FREE trial with full platform access. After the trial, you can choose from affordable subscription plans starting at just ₹20/day. No commission is ever taken from your rides.',
  },
  {
    q: 'What documents do I need to register?',
    a: 'You need a valid Aadhaar card, a driving license that matches your vehicle category, a photo of your vehicle, and a clear selfie. All documents are verified by our team within 24 hours.',
  },
  {
    q: 'How do I receive payments from riders?',
    a: 'Payments are made directly to you — either through cash or UPI. Gaman never holds or processes ride payments. 100% of every fare goes straight to your pocket.',
  },
  {
    q: 'Can I set my own fare for rides?',
    a: 'Yes! Gaman uses a bidding system where you see the rider\'s trip details and place your own price. There\'s no algorithm deciding your earnings — you decide what your time and fuel are worth.',
  },
  {
    q: 'What if my subscription expires mid-day?',
    a: 'You\'ll receive advance notifications before your subscription expires. If it does expire, you can instantly renew from within the app and get back online in seconds.',
  },
  {
    q: 'Is there a minimum number of rides I need to complete?',
    a: 'No! There are no minimum ride requirements, no penalties for going offline, and no forced ride assignments. Drive when you want, as much as you want.',
  },
  {
    q: 'How is Gaman different from driving for Ola or Uber?',
    a: 'With Ola/Uber, you lose 20-30% of every fare to commission. With Gaman, you pay a flat ₹20/day subscription and keep 100% of every fare. On 15 rides averaging ₹100 each, that\'s ₹4,000+ more in your pocket every month.',
  },
];

export default function ForDrivers() {
  const [openFaq, setOpenFaq] = useState(null);

  return (
    <div className="for-drivers-page">
      {/* Hero Section */}
      <section className="section fd-hero">
        <div className="container">
          <span className="badge-green">🚗 For Drivers</span>
          <h1>
            Drive on your<br />
            <span className="fd-gradient-text">own terms</span>
          </h1>
          <p className="fd-hero-sub">
            Earn fairly, drive freely. Zero commission, 100% of fares go directly to you.
            Join Gaman and take control of your earnings.
          </p>
          <div className="fd-hero-actions">
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-success"
            >
              📲 Download Gaman Driver
            </a>
            <a href="#earnings" className="btn btn-outline">
              💰 Calculate Earnings
            </a>
          </div>
          <div className="fd-hero-stats">
            <div className="fd-stat">
              <strong>0%</strong>
              <span>Commission</span>
            </div>
            <div className="fd-stat-divider" />
            <div className="fd-stat">
              <strong>100%</strong>
              <span>Fare is yours</span>
            </div>
            <div className="fd-stat-divider" />
            <div className="fd-stat">
              <strong>₹20/day</strong>
              <span>Flat subscription</span>
            </div>
          </div>
        </div>
      </section>

      {/* Subscription Plans Section */}
      <section className="section fd-pricing">
        <div className="container">
          <h2 className="fd-section-title">
            Simple, <span className="fd-gradient-text">Transparent</span> Pricing
          </h2>
          <p className="fd-section-subtitle">
            No commission. No hidden fees. Just a small daily subscription to access the platform.
          </p>
          <PricingCards />
        </div>
      </section>

      {/* KYC Process Section */}
      <section className="section fd-kyc">
        <div className="container">
          <h2 className="fd-section-title fd-title-dark">
            Get Started in <span className="fd-gradient-text">6 Easy Steps</span>
          </h2>
          <p className="fd-section-subtitle fd-subtitle-dark">
            Our KYC process is quick, simple, and fully digital. No office visits required.
          </p>
          <div className="fd-kyc-grid">
            {kycSteps.map((step) => (
              <div className="fd-kyc-card" key={step.number}>
                <div className="fd-kyc-number">{step.number}</div>
                <div className="fd-kyc-icon">{step.icon}</div>
                <h3>{step.title}</h3>
                <p>{step.desc}</p>
              </div>
            ))}
          </div>
          <div className="fd-kyc-note">
            <span>💡</span>
            <p>All documents are encrypted and stored securely. Your data is never shared with third parties.</p>
          </div>
        </div>
      </section>

      {/* Earnings Section */}
      <section className="section fd-earnings" id="earnings">
        <div className="container">
          <h2 className="fd-section-title fd-title-white">
            See How Much <span className="fd-gradient-text">More</span> You Earn
          </h2>
          <p className="fd-section-subtitle fd-subtitle-white">
            Compare your monthly earnings on Gaman vs other platforms. The difference is real.
          </p>
          <EarningsCalculator />
        </div>
      </section>

      {/* Driver FAQ Section */}
      <section className="section fd-faq">
        <div className="container">
          <h2 className="fd-section-title">
            Driver <span className="fd-gradient-text">FAQs</span>
          </h2>
          <p className="fd-section-subtitle">
            Common questions from drivers who are considering joining Gaman.
          </p>
          <div className="fd-faq-list">
            {driverFaqs.map((faq, i) => (
              <div
                className={`fd-faq-item ${openFaq === i ? 'open' : ''}`}
                key={i}
              >
                <button
                  className="fd-faq-question"
                  onClick={() => setOpenFaq(openFaq === i ? null : i)}
                >
                  <span>{faq.q}</span>
                  <span className="fd-faq-toggle">+</span>
                </button>
                <div className="fd-faq-answer">
                  <p>{faq.a}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Download CTA Section */}
      <section className="section fd-cta">
        <div className="container">
          <h2>Start Earning More Today</h2>
          <p>
            Download the Gaman Driver app now. Get a 7-day free trial — no payment required.
          </p>
          <a
            href="https://play.google.com/store"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-dark"
          >
            📲 Download Gaman Driver
          </a>
        </div>
      </section>
    </div>
  );
}
