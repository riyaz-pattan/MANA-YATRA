import './Home.css';
import heroMockup from '../assets/hero-mockup.png';
import ComparisonTable from '../components/ComparisonTable';
import EarningsCalculator from '../components/EarningsCalculator';
import PricingCards from '../components/PricingCards';
import AnimatedSection from '../components/AnimatedSection';

const stats = [
  { number: '0%', label: 'Commission on every ride' },
  { number: '₹20/day', label: 'Flat driver subscription' },
  { number: '7 days', label: 'Free trial — no card needed' },
  { number: '100%', label: 'Fare goes to your driver' },
];

const riderSteps = [
  'Enter your pickup and drop location',
  'Set your own bid price (or use the estimate)',
  'Watch drivers compete for your ride in real time',
  'Pick the best offer — by price, ETA, or driver rating',
  'Pay directly to your driver by cash or UPI',
];

const driverSteps = [
  'Download the Gaman Driver app',
  'Complete KYC — Aadhaar, Licence, Vehicle photo',
  'Choose your subscription (or start your 7-day free trial)',
  'Go online — see nearby ride requests on your map',
  'Place your bid and start earning 100% of every fare',
];

const riderFeatures = [
  {
    icon: '🎯',
    title: 'You set the price',
    desc: 'Enter your bid — drivers compete to give you the best fare.',
  },
  {
    icon: '👀',
    title: 'Full transparency',
    desc: 'See driver name, photo, vehicle, ETA, and bid price before you accept.',
  },
  {
    icon: '💸',
    title: 'No surge — ever',
    desc: 'Rain, peak hours, late night — the price is always market-driven, never algorithm-spiked.',
  },
  {
    icon: '📲',
    title: 'Pay your driver directly',
    desc: 'Cash or UPI straight to the driver. Gaman never touches your money.',
  },
  {
    icon: '🛡️',
    title: 'Ride-start OTP',
    desc: 'Your trip starts only after your 4-digit OTP is verified by the driver.',
  },
  {
    icon: '🗺️',
    title: 'Live tracking',
    desc: "Track your driver's approach and your entire trip in real time.",
  },
];

const testimonials = [
  {
    quote:
      'ఒక్క రోజు 18 rides chesanu. ₹1,800 earn chesanu. Gaman కి ₹20 pay chesanu. Balance full naaduye.',
    author: 'Raju K., Auto Driver, Secunderabad',
  },
  {
    quote:
      'Commission ledu, tension ledu. Daily ₹20 pay chesi, baaki antha naa pocket lo.',
    author: 'Suresh M., Bike Taxi, Kukatpally',
  },
  {
    quote:
      'First time aa app lo naa price nene fix chesanu. Very happy with Gaman.',
    author: 'Venkat R., Auto Driver, Dilsukhnagar',
  },
];

export default function Home() {
  return (
    <>
      <section className="hero">
        <AnimatedSection animation="fade-in-up" className="container">
          <div className="hero-text">
            <div className="hero-badge">
              <span className="badge-primary">Now live in Hyderabad 🛺</span>
            </div>

            <h1>
              The ride that pays
              <br />
              your driver — not
              <br />
              the platform.
            </h1>

            <p className="hero-sub">
              Zero commission. Transparent bidding.
              <br />
              100% of every fare goes directly to your driver.
            </p>

            <p className="hero-telugu telugu">
              మీ ride, మీ driver కి 100% చెల్లిస్తుంది.
            </p>

            <div className="hero-ctas">
              <a
                href="https://play.google.com/store"
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-success"
              >
                Download for Android
              </a>
            </div>

            <div className="hero-trust">
              <span>✓ 7-day free trial for drivers</span>
              <span>✓ Zero commission — forever</span>
              <span>✓ Direct UPI payments</span>
            </div>
          </div>

          <div className="hero-image">
            <img
              src={heroMockup}
              alt="Gaman app screenshot"
            />
          </div>
        </AnimatedSection>
      </section>

      <section className="stats-bar">
        <AnimatedSection animation="fade-in" delay={300} className="container">
          <div className="stats-grid">
            {stats.map((stat, i) => (
              <div className="stat-item" key={i}>
                <div className="stat-number">{stat.number}</div>
                <div className="stat-label">{stat.label}</div>
              </div>
            ))}
          </div>
        </AnimatedSection>
      </section>

      <section className="how-it-works section" id="how-it-works">
        <AnimatedSection animation="fade-in-up" className="container">
          <div className="section-header">
            <h2>How it works</h2>
          </div>

          <div className="how-columns">
            {/* For Riders */}
            <div className="how-column">
              <h3>
                <span className="emoji">🧑‍💼</span> For Riders
              </h3>
              <div className="how-steps">
                {riderSteps.map((step, i) => (
                  <div className="how-step" key={i}>
                    <div className="step-number">{i + 1}</div>
                    <div className="step-text">{step}</div>
                  </div>
                ))}
              </div>
              <p className="how-tagline">
                No surge. No algorithm. Just fair market pricing.
              </p>
            </div>

            {/* For Drivers */}
            <div className="how-column">
              <h3>
                <span className="emoji">🚗</span> For Drivers
              </h3>
              <div className="how-steps">
                {driverSteps.map((step, i) => (
                  <div className="how-step" key={i}>
                    <div className="step-number">{i + 1}</div>
                    <div className="step-text">{step}</div>
                  </div>
                ))}
              </div>
              <p className="how-tagline">
                No commission ever. Just ₹20 a day.
              </p>
            </div>
          </div>
        </AnimatedSection>
      </section>

      {/* ===== Section 4: Driver Benefits ===== */}
      <section className="driver-benefits section" id="driver-benefits">
        <AnimatedSection animation="fade-in-up" className="container">
          <div className="section-header">
            <h2>Why drivers are switching to Gaman</h2>
            <p className="section-sub-telugu telugu">
              ఒక్కసారి numbers చూడండి.
            </p>
          </div>

          <div className="driver-benefits-content">
            <ComparisonTable />
            <EarningsCalculator />
          </div>
        </AnimatedSection>
      </section>

      <section className="rider-features section" id="rider-features">
        <AnimatedSection animation="fade-in-up" className="container">
          <div className="section-header">
            <h2>Finally — a ride app that's fair to everyone</h2>
          </div>

          <div className="features-grid">
            {riderFeatures.map((feat, i) => (
              <div className="feature-card card-light" key={i}>
                <div className="feature-icon">{feat.icon}</div>
                <h3>{feat.title}</h3>
                <p>{feat.desc}</p>
              </div>
            ))}
          </div>
        </AnimatedSection>
      </section>

      {/* ===== Section: Referral Highlights ===== */}
      <section className="referral-highlight section" style={{ backgroundColor: 'var(--surface)', color: 'white', textAlign: 'center' }}>
        <AnimatedSection animation="zoom-in" className="container">
          <div className="badge-glow" style={{ marginBottom: 16 }}>🎁 New Feature</div>
          <h2 style={{ color: 'var(--white)' }}>Refer Drivers. Earn Free Rides.</h2>
          <p style={{ color: 'var(--text-grey)', fontSize: 18, maxWidth: 600, margin: '16px auto 32px' }}>
            Get 7 days of free subscription for every driver you refer to MANA YATRA. 
            No limits. More drivers = lower prices for riders and more earnings for you.
          </p>
          <a href="/referral" className="btn btn-primary btn-glow">Learn About Refer & Earn</a>
        </AnimatedSection>
      </section>

      {/* ===== Section 6: Testimonials ===== */}
      <section className="testimonials section" id="testimonials">
        <AnimatedSection animation="fade-in-up" className="container">
          <div className="section-header">
            <h2>Early drivers are already talking</h2>
          </div>

          <div className="testimonials-grid">
            {testimonials.map((t, i) => (
              <div className="testimonial-card" key={i}>
                <div className="testimonial-stars">⭐⭐⭐⭐⭐</div>
                <p className="testimonial-quote telugu">"{t.quote}"</p>
                <p className="testimonial-author">— {t.author}</p>
              </div>
            ))}
          </div>
        </AnimatedSection>
      </section>

      {/* ===== Section 7: Pricing ===== */}
      <section className="pricing-section section" id="pricing">
        <AnimatedSection animation="fade-in-up" className="container">
          <div className="section-header">
            <h2>Simple, honest pricing for drivers</h2>
            <p>No hidden fees. No per-ride cuts. Ever.</p>
          </div>

          <PricingCards />
        </AnimatedSection>
      </section>

      {/* ===== Section 8: Download CTA ===== */}
      <section className="download-cta section">
        <AnimatedSection animation="zoom-in" className="container">
          <h2>Download Gaman today</h2>
          <p className="cta-sub">
            Available on Android. Free to ride. Free to try for drivers.
          </p>
          <a
            href="https://play.google.com/store"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-dark"
          >
            Get it on Google Play
          </a>
          <p className="cta-telugu telugu">
            మన Hyderabad కి మన app. ఇప్పుడే download చేయండి.
          </p>
        </AnimatedSection>
      </section>
    </>
  );
}
