import './ReferralProgram.css';
import AnimatedSection from '../components/AnimatedSection';
import referralHero from '../assets/referral_hero.png';
import cinematicDriver from '../assets/cinematic_driver.png';

export default function ReferralProgram() {
  return (
    <>
      {/* Hero Section */}
      <section className="referral-hero">
        <div className="container">
          <AnimatedSection animation="fade-in-up" className="referral-hero-content">
            <div className="referral-badge">
              <span className="badge-glow">New Feature 🎁</span>
            </div>
            <h1>
              Refer Drivers.<br />
              <span className="text-glow">Earn Free Rides.</span>
            </h1>
            <p className="referral-hero-sub">
              For every friend who successfully joins MANA YATRA as a driver,
              you earn a full <strong>7-Day Free Subscription</strong>. Zero limits.
            </p>
            <div className="referral-hero-ctas">
              <a href="https://play.google.com/store" target="_blank" rel="noopener noreferrer" className="btn btn-primary btn-glow">
                Get Your Referral Code
              </a>
            </div>
          </AnimatedSection>
          
          <AnimatedSection animation="zoom-in" delay={200} className="referral-hero-image">
            <img src={referralHero} alt="Referral Reward Glowing Icon" className="hero-img-float" />
          </AnimatedSection>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="referral-how-it-works section">
        <div className="container">
          <AnimatedSection animation="fade-in-up">
            <div className="section-header center">
              <h2>How to earn your free trial</h2>
              <p>It's simple, transparent, and instantly rewarding.</p>
            </div>
          </AnimatedSection>

          <div className="referral-steps">
            <AnimatedSection animation="fade-in-up" delay={100} className="step-card card-glass">
              <div className="step-icon">1️⃣</div>
              <h3>Share Your Code</h3>
              <p>Find your unique referral code in the MANA YATRA Driver App under 'Refer & Earn'. Share it via WhatsApp or SMS.</p>
            </AnimatedSection>

            <AnimatedSection animation="fade-in-up" delay={200} className="step-card card-glass">
              <div className="step-icon">2️⃣</div>
              <h3>Friend Signs Up</h3>
              <p>Your friend enters your code during their onboarding process and completes their profile registration.</p>
            </AnimatedSection>

            <AnimatedSection animation="fade-in-up" delay={300} className="step-card card-glass">
              <div className="step-icon">3️⃣</div>
              <h3>You Both Win</h3>
              <p>Once their account is verified by our admins, your subscription is instantly extended by 7 days. No waiting!</p>
            </AnimatedSection>
          </div>
        </div>
      </section>

      {/* Cinematic Showcase Section */}
      <section className="cinematic-showcase">
        <div className="container cinematic-grid">
          <AnimatedSection animation="fade-in" className="cinematic-text">
            <h2>Drive your way.<br />Grow our community.</h2>
            <p>
              We believe in rewarding the drivers who help us build a fairer ride-hailing ecosystem. 
              MANA YATRA takes zero commissions. By inviting more drivers, you help us reduce prices for riders 
              while keeping 100% of your earnings.
            </p>
            <ul className="cinematic-benefits">
              <li>✓ Unlimited Referrals</li>
              <li>✓ Instant Subscription Extension</li>
              <li>✓ Track referrals in real-time in the app</li>
            </ul>
          </AnimatedSection>

          <AnimatedSection animation="zoom-in" delay={200} className="cinematic-image-wrapper">
            <img src={cinematicDriver} alt="Premium Driver at Night" className="cinematic-img" />
          </AnimatedSection>
        </div>
      </section>
    </>
  );
}
