import { useState } from 'react';
import ScrollVideoBackground from '../components/ScrollVideoBackground';
import './Home.css';

const riderSteps = [
  { title: 'Set Your Location', desc: 'Enter your pickup and drop-off location. Our smart search makes it quick and easy.' },
  { title: 'View Driver Bids', desc: 'Nearby drivers compete by offering you their best price. No surge pricing, ever.' },
  { title: 'Accept & Ride', desc: 'Pick the bid that works for you. Track your driver in real-time as they approach.' },
  { title: 'Pay & Rate', desc: 'Complete your ride with cashless payment. Rate your driver to help the community.' },
];

const driverSteps = [
  { title: 'Go Online', desc: 'Toggle your status to online from the dashboard. Smart Tracker starts automatically.' },
  { title: 'Get Ride Requests', desc: 'Receive nearby ride requests instantly. See pickup, drop-off, and distance details.' },
  { title: 'Place Your Bid', desc: 'Set your own fair price for the ride. You decide what you earn — zero commission taken.' },
  { title: 'Navigate & Earn', desc: 'Use built-in navigation to pick up the rider and complete the trip. 100% of the fare is yours.' },
];

const faqs = [
  {
    q: 'How is Gaman different from Ola and Uber?',
    a: 'Gaman charges ZERO commission from drivers. 100% of the fare goes directly to the driver. For riders, this means fair prices without hidden surge charges — drivers bid their own prices, creating healthy competition.',
  },
  {
    q: 'How does the bidding system work?',
    a: 'When you request a ride, nearby drivers can see your trip details and offer their price. You see all the bids in real-time and can choose the one that works best for you based on price, driver rating, and estimated arrival time.',
  },
  {
    q: 'Is Gaman safe to use?',
    a: 'Absolutely. All drivers go through KYC verification (Aadhaar, Driving License, Photo). Real-time ride tracking is shared with your emergency contacts via SOS. Your live location is visible throughout the ride.',
  },
  {
    q: 'How do I become a Gaman Driver?',
    a: 'Download the Gaman Driver app from the Play Store. Register with your phone number, upload your documents (Aadhaar, Driving License, Profile Photo), and wait for verification. Once approved, you can start earning immediately!',
  },
  {
    q: 'What payment methods are supported?',
    a: 'Currently, Gaman supports UPI and cash payments for riders. Drivers can manage their subscription plans through integrated Razorpay payments.',
  },
  {
    q: 'What are the subscription plans for drivers?',
    a: 'Gaman offers flexible subscription plans instead of per-ride commissions. New drivers get a 7-day free trial. After that, affordable daily/weekly plans keep you on the road without any per-ride deductions.',
  },
  {
    q: 'How can I delete my account and data?',
    a: 'You can request account deletion directly from the app under Settings. For more details, visit our Data Deletion page. All your personal data will be permanently removed from our servers within 30 days.',
  },
];

const features = [
  { icon: '🏷️', title: 'Zero Commission', desc: 'Unlike other platforms, we take absolutely no cut from the driver\'s earnings. Every rupee of the fare goes to the driver.' },
  { icon: '📍', title: 'Real-Time Tracking', desc: 'Track your driver live on the map from the moment they accept your ride until you reach your destination safely.' },
  { icon: '🛡️', title: 'Verified Drivers', desc: 'Every driver undergoes thorough KYC verification including Aadhaar, Driving License, and photo verification before they can accept rides.' },
  { icon: '⚡', title: 'Smart Matching', desc: 'Our geohash-based matching system connects you with the nearest available drivers in seconds, not minutes.' },
  { icon: '🚨', title: 'SOS Emergency', desc: 'One-tap SOS button shares your live location and ride details with emergency contacts instantly during any ride.' },
  { icon: '📊', title: 'Transparent Pricing', desc: 'No hidden charges, no surge pricing. Drivers bid their own fare and riders choose. Complete transparency for everyone.' },
];

export default function Home() {
  const [activeTab, setActiveTab] = useState('rider');
  const [openFaq, setOpenFaq] = useState(null);
  const steps = activeTab === 'rider' ? riderSteps : driverSteps;

  return (
    <div id="home-page">
      {/* Hero with scroll video */}
      <ScrollVideoBackground videoSrc={null} />

      {/* Mission Section */}
      <section className="section mission-section" id="mission">
        <div className="container">
          <h2 className="section-title">
            Our <span className="gradient-text">Mission</span>
          </h2>
          <p className="section-subtitle">
            We believe mobility should be fair for everyone — riders and drivers
            alike. Gaman is built on three core pillars.
          </p>
          <div className="mission-cards">
            <div className="glass-card mission-card">
              <div className="mission-card-icon">💰</div>
              <h3>Zero Commission</h3>
              <p>
                Drivers keep 100% of every fare. No hidden deductions, no
                per-ride cuts. Just a simple, affordable subscription to stay
                active on the platform.
              </p>
            </div>
            <div className="glass-card mission-card">
              <div className="mission-card-icon">⚖️</div>
              <h3>Fair Pricing</h3>
              <p>
                Our bidding system eliminates surge pricing. Multiple drivers
                compete to offer you the best price, ensuring you always get a
                fair deal.
              </p>
            </div>
            <div className="glass-card mission-card">
              <div className="mission-card-icon">🤝</div>
              <h3>Driver First</h3>
              <p>
                We call our drivers "Partners" because that's what they are.
                Gaman is designed to empower drivers with dignity, respect, and
                financial freedom.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="section how-it-works-section" id="how-it-works">
        <div className="container">
          <h2 className="section-title">
            How <span className="gradient-text">It Works</span>
          </h2>
          <p className="section-subtitle">
            Whether you're a rider booking a trip or a driver earning a living,
            Gaman keeps it simple.
          </p>
          <div className="how-tabs">
            <button
              className={`how-tab ${activeTab === 'rider' ? 'active' : ''}`}
              onClick={() => setActiveTab('rider')}
            >
              🚶 For Riders
            </button>
            <button
              className={`how-tab ${activeTab === 'driver' ? 'active' : ''}`}
              onClick={() => setActiveTab('driver')}
            >
              🚗 For Drivers
            </button>
          </div>
          <div className="how-steps">
            {steps.map((step, i) => (
              <div className="glass-card how-step" key={i}>
                <div className="how-step-number">{i + 1}</div>
                <h3>{step.title}</h3>
                <p>{step.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Stats */}
      <section className="section stats-section">
        <div className="container">
          <div className="stats-grid">
            <div className="stat-item">
              <h3 className="gradient-text">0%</h3>
              <p>Commission Charged</p>
            </div>
            <div className="stat-item">
              <h3 className="gradient-text">100%</h3>
              <p>Earnings to Drivers</p>
            </div>
            <div className="stat-item">
              <h3 className="gradient-text">Real-Time</h3>
              <p>Bid Based Pricing</p>
            </div>
            <div className="stat-item">
              <h3 className="gradient-text">24/7</h3>
              <p>Support Available</p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="section features-section" id="features">
        <div className="container">
          <h2 className="section-title">
            Why Choose <span className="gradient-text">Gaman</span>
          </h2>
          <p className="section-subtitle">
            Built from the ground up to be fair, fast, and safe for everyone.
          </p>
          <div className="features-grid">
            {features.map((f, i) => (
              <div className="glass-card feature-card" key={i}>
                <div className="feature-card-icon">{f.icon}</div>
                <div>
                  <h3>{f.title}</h3>
                  <p>{f.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="section faq-section" id="faq">
        <div className="container">
          <h2 className="section-title">
            Frequently Asked <span className="gradient-text">Questions</span>
          </h2>
          <p className="section-subtitle">
            Got questions? We've got answers.
          </p>
          <div className="faq-list">
            {faqs.map((faq, i) => (
              <div
                className={`faq-item ${openFaq === i ? 'open' : ''}`}
                key={i}
              >
                <button
                  className="faq-question"
                  onClick={() => setOpenFaq(openFaq === i ? null : i)}
                >
                  <span>{faq.q}</span>
                  <span className="faq-toggle">+</span>
                </button>
                <div className="faq-answer">
                  <p>{faq.a}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="section cta-section">
        <div className="container">
          <div className="cta-content">
            <h2>
              Ready to <span className="gradient-text">Ride?</span>
            </h2>
            <p>
              Download Gaman today and experience rides the way they should be
              — fair, transparent, and rewarding.
            </p>
            <div className="cta-buttons">
              <a
                href="https://play.google.com/store"
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-primary"
              >
                📱 Get Gaman for Riders
              </a>
              <a
                href="https://play.google.com/store"
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-secondary"
              >
                🚗 Get Gaman for Drivers
              </a>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
