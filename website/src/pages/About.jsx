import './About.css';

const missionCards = [
  {
    icon: '⚖️',
    title: 'Fair Travel',
    description: 'Every ride should be priced fairly. Our bid-based system eliminates surge pricing and lets market dynamics work in favour of both riders and drivers.',
  },
  {
    icon: '💪',
    title: 'Driver Empowerment',
    description: 'Drivers are partners, not gig workers. They set their own prices, keep 100% of their fares, and operate with dignity and financial independence.',
  },
  {
    icon: '🤝',
    title: 'Community First',
    description: 'Gaman is built for Hyderabad, by Hyderabad. We prioritize local needs, local drivers, and building a mobility ecosystem that serves our community.',
  },
];

export default function About() {
  return (
    <div className="about-page">
      {/* Hero Section */}
      <section className="about-hero">
        <div className="container">
          <span className="badge-purple">🏙️ Made in Hyderabad</span>
          <h1>Built in Hyderabad.<br />Built for Hyderabad.</h1>
          <p className="about-hero-telugu telugu">
            మన city, మన app, మన drivers.
          </p>
        </div>
      </section>

      {/* Founding Story Section */}
      <section className="section about-story-section">
        <div className="container">
          <div className="story-content">
            <div className="story-text">
              <span className="badge-purple">💡 Our Story</span>
              <h2>Why we built Gaman</h2>
              <p>
                Every day, thousands of drivers in Hyderabad wake up before dawn, navigate through traffic, and work 12-14 hour shifts — only to hand over 20-30% of their hard-earned money to ride-hailing platforms. That's not a partnership. That's exploitation.
              </p>
              <p>
                We started Gaman because we believe the people who do the work should keep the money. It's that simple. No complicated revenue-sharing formulas, no hidden platform fees, no surge pricing that benefits the platform more than the driver.
              </p>
              <p>
                Gaman operates on a flat subscription model. Drivers pay a small daily, weekly, or monthly fee and keep <strong>100% of every fare</strong>. The more rides they complete, the more they earn — without a platform taking a bigger slice.
              </p>
            </div>
            <div className="story-stats">
              <div className="story-stat-card card-light">
                <h3>0%</h3>
                <p>Commission charged to drivers</p>
              </div>
              <div className="story-stat-card card-light">
                <h3>100%</h3>
                <p>Earnings go to the driver</p>
              </div>
              <div className="story-stat-card card-light">
                <h3>₹18</h3>
                <p>Per day — our lowest plan cost</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Mission Section */}
      <section className="section about-mission-section">
        <div className="container">
          <div className="about-mission-header">
            <span className="badge-green">🎯 Our Mission</span>
            <h2>What drives us</h2>
            <p className="about-mission-subtitle">
              Three principles guide everything we build at Gaman.
            </p>
          </div>
          <div className="about-mission-grid">
            {missionCards.map((card, i) => (
              <div className="about-mission-card card-light" key={i}>
                <div className="about-mission-icon">{card.icon}</div>
                <h3>{card.title}</h3>
                <p>{card.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Team Section */}
      <section className="section about-team-section">
        <div className="container">
          <div className="about-team-content">
            <span className="badge-purple">👥 Our Team</span>
            <h2>The people behind Gaman</h2>
            <p className="about-team-description">
              Our team is growing. We're a small, passionate group based in Hyderabad, building the future of fair mobility. We come from diverse backgrounds — tech, transportation, design — but share one common belief: drivers deserve better.
            </p>
            <div className="about-team-cta">
              <p className="about-team-join">
                Interested in joining us? We're always looking for people who care about making a difference.
              </p>
              <a href="mailto:support@manayatra.com" className="btn btn-primary">
                Get in Touch
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="section about-cta-section">
        <div className="container">
          <h2>Join the movement</h2>
          <p>
            Whether you're a rider looking for fair prices or a driver who wants to keep what you earn — Gaman is for you.
          </p>
          <div className="about-cta-buttons">
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-dark"
            >
              📱 Get Gaman for Riders
            </a>
            <a
              href="https://play.google.com/store"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-outline"
            >
              🚗 Get Gaman for Drivers
            </a>
          </div>
        </div>
      </section>
    </div>
  );
}
